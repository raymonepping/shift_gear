"""The rotation controller: decide, rotate with CAS, record — and serve status.

Stateless by design. Every loop re-reads Vault: current version, history
records, read counts, pending requests and watched paths all live in KV v2
metadata. Restarting, removing or scaling the controller cannot lose or
duplicate a rotation: a concurrent writer simply loses the CAS race and
skips.

Environment (ROTATION_*):
  ROTATION_CONFIG         rendered JSON config            (required)
  ROTATION_VAULT_ADDR     agent api_proxy, e.g. http://127.0.0.1:8100
  ROTATION_NAMESPACE      Vault namespace, e.g. shift-gear
  ROTATION_AUDIT_URL      audit collector base URL (usage strategy); empty = usage not available
  ROTATION_EVENTS_FILE    NDJSON from the vault-events sidecar; missing = polling mode
  ROTATION_HTTP_PORT      status port (default 8080)
  ROTATION_TEST_MODE      "1" enables test-only hooks (never set outside rotation-test)
  ROTATION_TEST_PAUSE_AFTER_WRITE  seconds to sleep between write and record (test mode only)
  ROTATION_TEST_PAUSE_SECRET       the one secret (<type>/<name>) that pause applies to
"""
from __future__ import annotations

import json
import logging
import os
import signal
import threading
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import __version__, compliance, history as h, triggers
from .config import Config, Secret, describe, load
from .events import EventTail
from .generators import generate, policy_violations
from .redact import REGISTRY, configure_logging, fingerprint, log
from .usage import UsageCounter
from .vault import CasConflict, Metadata, Unreachable, Vault, VaultError, iso, iso_precise, parse_time


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Controller:
    def __init__(self, config: Config, vault: Vault, usage: UsageCounter | None,
                 events: EventTail | None, logger: logging.Logger, test_mode: bool = False,
                 pause_after_write: float = 0.0, pause_secret: str = ""):
        self.config = config
        self.vault = vault
        self.usage = usage
        self.events = events
        self.logger = logger
        self.test_mode = test_mode
        self.pause_after_write = pause_after_write if test_mode else 0.0
        self.pause_secret = pause_secret
        self.wake = threading.Event()
        self.stop = threading.Event()
        self.lock = threading.Lock()
        self.status: dict[str, dict] = {}
        self.last_loop: datetime | None = None
        self.last_error: str | None = None
        self.identity: str | None = None
        self.counters = {"rotations": 0, "cas_skips": 0, "enforced": 0, "errors": 0, "loops": 0}
        self.retire_scan_due = 0
        self.usage_state = {"available": usage is not None, "undercount": False, "reason": ""}

    # -- identity ---------------------------------------------------------
    def learn_identity(self) -> None:
        """Ask Vault who we are, so our own reads are not counted as usage."""
        if self.identity:
            return
        info = self.vault.lookup_self()
        self.identity = str(info.get("display_name") or "")
        if self.usage and self.identity:
            self.usage.exclude_display_names.add(self.identity)
        log(self.logger, "identity", display_name=self.identity, policies=info.get("policies"))

    # -- one loop -----------------------------------------------------------
    def loop_once(self) -> None:
        now = utcnow()
        self.counters["loops"] += 1
        try:
            self.learn_identity()
        except (Unreachable, VaultError) as exc:
            self.last_error = f"vault not ready: {exc}"
            log(self.logger, "waiting for vault", level=logging.WARNING, reason=str(exc))
            return

        # On the first loop that reaches Vault, then every 30 loops.
        if self.counters["loops"] >= self.retire_scan_due:
            self.retire_scan_due = self.counters["loops"] + 30
            try:
                self.retire_unconfigured()
            except VaultError as exc:
                log(self.logger, "retire scan failed", level=logging.WARNING, error=str(exc))

        reads: dict[str, list[datetime]] = {}
        if self.usage is not None:
            poll = self.usage.poll({s.rel_path for s in self.config.secrets if "usage" in s.strategies})
            self.usage_state = {"available": poll.available, "undercount": poll.undercount, "reason": poll.reason}
            reads = poll.reads
        changed_paths: set[str] = set()
        if self.events is not None:
            changed_paths = {e.rel_path for e in self.events.read()}

        for secret in self.config.secrets:
            try:
                self.process(secret, now, reads.get(secret.rel_path, []), changed_paths)
            except Unreachable as exc:
                self.last_error = str(exc)
                log(self.logger, "vault unreachable", level=logging.WARNING, secret=secret.id)
                break
            except VaultError as exc:
                self.counters["errors"] += 1
                self.last_error = str(exc)
                log(self.logger, "vault error", level=logging.ERROR, secret=secret.id, error=str(exc))
        self.last_loop = utcnow()

    def process(self, secret: Secret, now: datetime, new_reads: list[datetime], changed_paths: set[str]) -> None:
        md = self.vault.read_metadata(secret.rel_path)
        if md is None or md.current_version == 0:
            self.onboard(secret)
            md = self.vault.read_metadata(secret.rel_path)
            if md is None:
                return
        self.reconcile(secret, md)
        self.recover(secret, md)
        md = self.vault.read_metadata(secret.rel_path) or md

        reads_since = self.update_reads(secret, md, new_reads)
        watches = self.watch_state(secret)
        recorded = h.parse_watch(md.custom.get(h.WATCH))
        if any(p not in recorded for p in watches):
            # A watch added after onboarding starts from the current version: no retroactive trigger.
            recorded = {**{p: v for p, v in watches.items() if p not in recorded}, **recorded}
            self.vault.patch_metadata(secret.rel_path, {h.WATCH: h.encode_watch(recorded)})
        # Any difference counts: a newer version, a recreated path (version back
        # to 1) or a deleted one (0). The checkpoint only advances when a
        # rotation is recorded, so a skipped or crashed rotation fires again.
        changed = tuple(p for p, v in watches.items() if v != recorded.get(p, v))
        if changed_paths & {e.path for e in secret.events}:
            log(self.logger, "event received", secret=secret.id,
                paths=sorted(changed_paths & {e.path for e in secret.events}))

        request = h.parse_request(md.custom.get(h.REQUEST))
        if request and request[0] == md.custom.get(h.SERVED):
            request = None
        state = triggers.State(
            last_rotated=md.created(md.current_version),
            reads_since=reads_since if self.usage_state["available"] else None,
            pending_request=request,
            changed_watches=changed,
        )
        trigger = triggers.decide(secret, state, now)
        if trigger is not None:
            self.rotate(secret, md, trigger, watches)
            md = self.vault.read_metadata(secret.rel_path) or md
            state = triggers.State(md.created(md.current_version), 0 if self.usage_state["available"] else None)
        self.publish_status(secret, md, state)

    # -- steps ----------------------------------------------------------------
    def onboard(self, secret: Secret) -> None:
        """Create v1: metadata first (cas_required on), then the value with cas=0."""
        custom = {
            h.MANAGED_BY: h.MANAGED_BY_VALUE,
            h.TYPE: secret.type.name,
            h.OWNER: secret.owner,
            h.STRATEGIES: ",".join(secret.strategies),
            h.READS_SINCE: "0",
        }
        watches = self.watch_state(secret)
        if watches:
            custom[h.WATCH] = h.encode_watch(watches)
        self.vault.write_metadata(secret.rel_path, self.config.max_versions, True, custom)
        value = self.new_value(secret, previous_fp=None)
        try:
            version = self.vault.write_value(secret.rel_path, value, cas=0)
        except CasConflict:
            self.counters["cas_skips"] += 1
            log(self.logger, "onboard skipped: someone created it first", secret=secret.id)
            return
        record = h.Record(version, fingerprint(value), "created", iso(utcnow()), "controller")
        self.vault.patch_metadata(secret.rel_path, {h.key(version): record.encode(),
                                                    h.LAST_ROTATED: record.at, h.LAST_TRIGGER: "created"})
        log(self.logger, "onboarded", secret=secret.id, version=version, fp=record.fingerprint)

    def retire_unconfigured(self) -> None:
        """A secret that left rotation.yaml stays in Vault with its history, but is
        visibly no longer managed: the marker goes, a retirement time is stamped."""
        configured = {s.rel_path for s in self.config.secrets}
        for type_dir in self.vault.list_metadata(self.config.prefix):
            if not type_dir.endswith("/"):
                continue
            for name in self.vault.list_metadata(f"{self.config.prefix}/{type_dir.rstrip('/')}"):
                rel = f"{self.config.prefix}/{type_dir}{name}"
                if name.endswith("/") or rel in configured:
                    continue
                md = self.vault.read_metadata(rel)
                if md and md.custom.get(h.MANAGED_BY) == h.MANAGED_BY_VALUE:
                    self.vault.patch_metadata(rel, {h.MANAGED_BY: None, h.RETIRED_AT: iso(utcnow())})
                    log(self.logger, "retired", secret=rel.removeprefix(self.config.prefix + "/"),
                        note="no longer in rotation.yaml; value and history kept")

    def reconcile(self, secret: Secret, md: Metadata) -> None:
        """Enforcement layer 1: settings and markers follow the configuration."""
        fixes: dict = {}
        custom: dict[str, str | None] = {}
        if md.max_versions != self.config.max_versions:
            fixes["max_versions"] = self.config.max_versions
        if not md.cas_required:
            fixes["cas_required"] = True
        wanted = {h.MANAGED_BY: h.MANAGED_BY_VALUE, h.TYPE: secret.type.name, h.OWNER: secret.owner,
                  h.STRATEGIES: ",".join(secret.strategies)}
        if h.RETIRED_AT in md.custom:
            custom[h.RETIRED_AT] = None             # managed again
        for k, v in wanted.items():
            if md.custom.get(k) != v:
                custom[k] = v
        if not fixes and not custom:
            return
        self.vault.patch_metadata(secret.rel_path, custom or None, **fixes)
        self.counters["enforced"] += 1
        changes = {k: f"{getattr(md, k)}->{v}" for k, v in fixes.items()}
        changes.update({k: f"{md.custom.get(k)}->{v}" for k, v in custom.items()})
        log(self.logger, "enforced", secret=secret.id, changes=changes)

    def recover(self, secret: Secret, md: Metadata) -> None:
        """Versions written without a record (crash between write and record, or a foreign write)."""
        records = h.decode(md.custom)
        oldest_kept = md.current_version - self.config.max_versions + 1
        missing = [v for v, info in md.versions.items()
                   if v >= max(1, oldest_kept) and v not in records and not info.get("destroyed")]
        if not missing:
            return
        patch: dict[str, str | None] = {}
        for version in sorted(missing):
            value = self.vault.read_value(secret.rel_path, version)
            fp = fingerprint(value) if value else "unknown"
            created = md.created(version)
            patch[h.key(version)] = h.Record(version, fp, "recovered",
                                             iso(created) if created else iso(utcnow()), "unknown").encode()
        self.vault.patch_metadata(secret.rel_path, patch)
        log(self.logger, "recovered unrecorded versions", level=logging.WARNING,
            secret=secret.id, versions=sorted(missing))

    def update_reads(self, secret: Secret, md: Metadata, new_reads: list[datetime]) -> int:
        current = int(md.custom.get(h.READS_SINCE) or 0) if (md.custom.get(h.READS_SINCE) or "0").isdigit() else 0
        if "usage" not in secret.strategies or not new_reads:
            return current
        since = md.created(md.current_version)
        cursor = parse_time(md.custom.get(h.READS_CURSOR))
        counted = [t for t in new_reads if (since is None or t > since) and (cursor is None or t > cursor)]
        if not counted:
            return current
        total = current + len(counted)
        self.vault.patch_metadata(secret.rel_path,
                                  {h.READS_SINCE: str(total), h.READS_CURSOR: iso_precise(max(counted))})
        log(self.logger, "usage", secret=secret.id, reads_since=total, max_reads=secret.max_reads)
        return total

    def watch_state(self, secret: Secret) -> dict[str, int]:
        """Current version of every watched path (metadata read only — never the value)."""
        out: dict[str, int] = {}
        for rule in secret.events:
            md = self.vault.read_metadata(rule.path)
            out[rule.path] = md.current_version if md else 0
        return out

    def new_value(self, secret: Secret, previous_fp: str | None) -> str:
        for _ in range(5):
            value = generate(secret.type.generator)
            if fingerprint(value) != previous_fp and not policy_violations(value, secret.type):
                REGISTRY.add(value)
                return value
        raise RuntimeError(f"{secret.id}: generator could not produce a compliant, different value")

    def rotate(self, secret: Secret, md: Metadata, trigger: triggers.Trigger, watches: dict[str, int]) -> None:
        records = h.decode(md.custom)
        previous = records.get(md.current_version)
        value = self.new_value(secret, previous.fingerprint if previous else None)
        try:
            version = self.vault.write_value(secret.rel_path, value, cas=md.current_version)
        except CasConflict:
            self.counters["cas_skips"] += 1
            log(self.logger, "skip: version changed since read (CAS)", secret=secret.id,
                expected=md.current_version)
            return
        if self.pause_after_write and secret.id == self.pause_secret:
            time.sleep(self.pause_after_write)      # rotation-test s08 crash window, one secret only
        at = iso(utcnow())
        record = h.Record(version, fingerprint(value), trigger.kind, at, trigger.actor)
        patch: dict[str, str | None] = {
            h.key(version): record.encode(),
            h.LAST_ROTATED: at,
            h.LAST_TRIGGER: trigger.kind,
            h.READS_SINCE: "0",
            h.READS_CURSOR: iso_precise(utcnow()),
        }
        if trigger.request_id:
            patch[h.SERVED] = trigger.request_id
        if watches:
            patch[h.WATCH] = h.encode_watch(watches)
        merged = dict(md.custom, **{k: v for k, v in patch.items() if v is not None})
        patch.update(h.prune_keys(merged, version, self.config.max_versions))
        self.vault.patch_metadata(secret.rel_path, patch)
        self.counters["rotations"] += 1
        log(self.logger, "rotated", secret=secret.id, version=f"v{md.current_version}->v{version}",
            fp=f"{previous.fingerprint if previous else '?'}->{record.fingerprint}",
            trigger=trigger.kind, detail=trigger.detail, actor=trigger.actor)

    def publish_status(self, secret: Secret, md: Metadata, state: triggers.State) -> None:
        records = h.decode(md.custom)
        current = records.get(md.current_version)
        with self.lock:
            self.status[secret.id] = {
                "secret": secret.id,
                "path": f"{self.config.mount}/{secret.rel_path}",
                "type": secret.type.name,
                "owner": secret.owner,
                "strategies": list(secret.strategies),
                "version": md.current_version,
                "fingerprint": current.fingerprint if current else None,
                "last_rotated": md.custom.get(h.LAST_ROTATED),
                "last_trigger": md.custom.get(h.LAST_TRIGGER),
                "reads_since": state.reads_since,
                "max_reads": secret.max_reads if "usage" in secret.strategies else None,
                "next_due": triggers.next_due(secret, state),
                "compliance": compliance.evaluate(secret, self.config, md, utcnow(),
                                                  reads_reported=self.usage_state["available"]),
            }

    # -- views ----------------------------------------------------------------
    def snapshot(self) -> dict:
        with self.lock:
            secrets = [dict(v) for v in self.status.values()]
        return {
            "controller": {
                "version": __version__,
                "identity": self.identity,
                "last_loop": iso(self.last_loop) if self.last_loop else None,
                "loop_seconds": self.config.loop_seconds,
                "last_error": self.last_error,
                "events": ("live" if self.events is not None and self.events.available else "polling"),
                "usage": self.usage_state,
                "counters": dict(self.counters),
            },
            "config": describe(self.config),
            "secrets": secrets,
        }

    def compliance_report(self) -> dict:
        with self.lock:
            results = [dict(v["compliance"]) for v in self.status.values()]
        return {"summary": compliance.summary(results, utcnow(), "running"), "secrets": results}

    def healthy(self) -> bool:
        if self.last_loop is None:
            return True     # starting; readiness must not depend on Vault being up
        return (utcnow() - self.last_loop).total_seconds() < max(60, 6 * self.config.loop_seconds)

    def metrics(self) -> str:
        lines = [f"rotation_controller_{k}_total {v}" for k, v in self.counters.items()]
        with self.lock:
            for item in self.status.values():
                label = f'secret="{item["secret"]}"'
                lines.append(f"rotation_secret_version{{{label}}} {item['version']}")
                lines.append(f"rotation_secret_compliant{{{label}}} {int(item['compliance']['compliant'])}")
        return "\n".join(lines) + "\n"

    # -- operator requests (loopback only) --------------------------------------
    def request(self, secret_id: str, actor: str, reason: str) -> dict:
        """Record a rotation request in Vault (rotation_request) and wake the loop.

        Reached only over loopback, i.e. through `oc exec` into this pod, so the
        authority is Kubernetes RBAC on pods/exec in this namespace. The request
        goes through Vault like a console request, and the actor says how it came.
        """
        secret = self.config.secret(secret_id)
        if "event" not in secret.strategies:
            raise ValueError(f"{secret.id}: strategy 'event' is not enabled — requests are not served")
        md = self.vault.read_metadata(secret.rel_path)
        request_id = str(uuid.uuid4())
        self.vault.patch_metadata(secret.rel_path, {h.REQUEST: h.encode_request(request_id, actor, reason)})
        log(self.logger, "rotation requested", secret=secret.id, actor=actor, reason=reason, request=request_id[:8])
        self.wake.set()
        return {"secret": secret.id, "request_id": request_id, "version": md.current_version if md else 0}

    # -- run ------------------------------------------------------------------
    def run(self) -> None:
        log(self.logger, "starting", version=__version__, secrets=[s.id for s in self.config.secrets],
            events="file" if self.events else "none", usage=self.usage is not None)
        while not self.stop.is_set():
            try:
                self.loop_once()
            except Exception as exc:  # keep the loop alive; the error is reported, never swallowed
                self.counters["errors"] += 1
                self.last_error = f"{exc.__class__.__name__}: {exc}"
                self.logger.exception("loop failed")
            self.wake.wait(self.config.loop_seconds)
            self.wake.clear()


def make_handler(controller: Controller):
    class Handler(BaseHTTPRequestHandler):
        def _send(self, code: int, body: str, ctype: str = "application/json") -> None:
            data = body.encode()
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):  # noqa: N802 - http.server API
            path = self.path.split("?")[0]
            if path == "/healthz":
                ok = controller.healthy()
                self._send(200 if ok else 503, json.dumps({"ok": ok}))
            elif path == "/status":
                self._send(200, json.dumps(controller.snapshot()))
            elif path == "/compliance":
                self._send(200, json.dumps(controller.compliance_report()))
            elif path == "/metrics":
                self._send(200, controller.metrics(), "text/plain; version=0.0.4")
            else:
                self._send(404, json.dumps({"error": "not found"}))

        def do_POST(self):  # noqa: N802 - http.server API
            # Loopback only: the NetworkPolicy already limits ingress to the
            # console's read-only calls; this guards the one write regardless.
            if (controller.test_mode and self.client_address[0] in ("127.0.0.1", "::1")
                    and self.path.split("?")[0] == "/test/short-write"):
                self._test_short_write()
                return
            if self.client_address[0] not in ("127.0.0.1", "::1") or self.path.split("?")[0] != "/request":
                self._send(403 if self.path.startswith("/request") else 404, json.dumps({"error": "forbidden"}))
                return
            try:
                length = min(int(self.headers.get("Content-Length") or 0), 4096)
                body = json.loads(self.rfile.read(length) or b"{}")
                result = controller.request(str(body["secret"]), str(body.get("actor") or "cli")[:120],
                                            str(body.get("reason") or "manual request")[:200])
                self._send(202, json.dumps(result))
            except (KeyError, ValueError) as exc:
                self._send(400, json.dumps({"error": str(exc)}))
            except (VaultError, Unreachable) as exc:
                self._send(503, json.dumps({"error": str(exc)}))

        def _test_short_write(self) -> None:
            """rotation-test s12 only (test mode): prove the Sentinel EGP holds even
            the controller to its type policy, by attempting a too-short value."""
            try:
                length = min(int(self.headers.get("Content-Length") or 0), 1024)
                secret = controller.config.secret(str(json.loads(self.rfile.read(length) or b"{}")["secret"]))
                md = controller.vault.read_metadata(secret.rel_path)
                controller.vault.write_value(secret.rel_path, "x" * 8, cas=md.current_version if md else 0)
                self._send(200, json.dumps({"status": 200, "note": "written — the EGP did NOT refuse it"}))
            except VaultError as exc:
                log(controller.logger, "policy-refused (test)", level=logging.WARNING, status=exc.status)
                self._send(200, json.dumps({"status": exc.status}))
            except (KeyError, ValueError) as exc:
                self._send(400, json.dumps({"error": str(exc)}))

        def log_message(self, fmt, *args):  # quiet access log
            return

    return Handler


def main() -> None:
    logger = configure_logging()
    config = load(os.environ["ROTATION_CONFIG"])
    namespace = os.environ.get("ROTATION_NAMESPACE", "")
    vault = Vault(os.environ.get("ROTATION_VAULT_ADDR", "http://127.0.0.1:8100"), namespace, config.mount)
    audit_url = os.environ.get("ROTATION_AUDIT_URL", "")
    usage = UsageCounter(audit_url, config.mount, namespace) if audit_url else None
    events_file = os.environ.get("ROTATION_EVENTS_FILE", "")
    events = EventTail(events_file, config.mount) if events_file else None
    test_mode = os.environ.get("ROTATION_TEST_MODE") == "1"
    controller = Controller(config, vault, usage, events, logger, test_mode,
                            float(os.environ.get("ROTATION_TEST_PAUSE_AFTER_WRITE", "0") or 0),
                            os.environ.get("ROTATION_TEST_PAUSE_SECRET", ""))

    server = ThreadingHTTPServer(("0.0.0.0", int(os.environ.get("ROTATION_HTTP_PORT", "8080"))),
                                 make_handler(controller))
    threading.Thread(target=server.serve_forever, daemon=True).start()

    def _stop(*_):
        controller.stop.set()
        controller.wake.set()
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    if events is not None:
        def _watch_events():
            while not controller.stop.is_set():
                if events.available and os.path.getsize(events.path) > events._offset:
                    controller.wake.set()
                time.sleep(1)
        threading.Thread(target=_watch_events, daemon=True).start()

    controller.run()
    server.shutdown()


if __name__ == "__main__":
    main()
