"""The consumer process: poll the Agent snapshot, hot-reload, exercise the door.

Settings (CONSUMER_*; never VAULT_*):
  CONSUMER_SECRET            display id, e.g. api-key/secure-door
  CONSUMER_SNAPSHOT_FILE     Agent-rendered JSON (memory-backed volume, read-only here)
  CONSUMER_PROBE_FILE        vault-probe result (/health/vault.json)
  CONSUMER_AGENT_LOG         Agent log file, scanned for refresh/fetch-error evidence
  CONSUMER_STATUS_FILE       non-secret status for the board (/status/state.json)
  CONSUMER_STATE_FILE        last seen version (non-secret, persistent) for restart gaps
  CONSUMER_POLL_S            local file poll interval (default 1)
  CONSUMER_VALIDATE_S        Secure Door check interval (default 10)
  CONSUMER_STALE_AFTER_S     unreachable this long -> stale (default 60)
  CONSUMER_RENDER_INTERVAL_S the Agent's configured static_secret_render_interval (display only)
  CONSUMER_LOG_LEVEL         INFO | DEBUG
"""
from __future__ import annotations

import json
import os
import signal
import statistics
import sys
import tempfile
import threading
import time
from collections import deque
from datetime import datetime, timezone

from . import __version__, door as door_mod, health, snapshot
from .health import iso, parse_time, utcnow

LEVELS = {"DEBUG": 10, "INFO": 20, "WARN": 30, "ERROR": 40}


class Consumer:
    def __init__(self, env: dict[str, str] | None = None, out=sys.stdout):
        e = env if env is not None else dict(os.environ)
        self.secret = e.get("CONSUMER_SECRET", "api-key/secure-door")
        self.snapshot_file = e.get("CONSUMER_SNAPSHOT_FILE", "/vault/render/secret.json")
        self.probe_file = e.get("CONSUMER_PROBE_FILE", "/health/vault.json")
        self.agent_log = e.get("CONSUMER_AGENT_LOG", "/agent-log/agent.log")
        self.status_file = e.get("CONSUMER_STATUS_FILE", "/status/state.json")
        self.state_file = e.get("CONSUMER_STATE_FILE", "/state/last-version.json")
        self.poll_s = float(e.get("CONSUMER_POLL_S", "1"))
        self.validate_s = float(e.get("CONSUMER_VALIDATE_S", "10"))
        self.stale_after_s = float(e.get("CONSUMER_STALE_AFTER_S", "60"))
        self.render_interval_s = float(e.get("CONSUMER_RENDER_INTERVAL_S", "5"))
        self.level = LEVELS.get(e.get("CONSUMER_LOG_LEVEL", "INFO").upper(), 20)
        self.out = out
        self.door = door_mod.SecureDoor(self.snapshot_file)
        self.cached: snapshot.Snapshot | None = None
        self.loaded_at: datetime | None = None
        self.started_at = utcnow()
        self.snapshot_problem: str | None = None
        self.probe = health.VaultProbe()
        self.agent = health.AgentEvidence()
        self.last_door: dict | None = None
        self.rotations: deque[dict] = deque(maxlen=50)
        self.log_ring: deque[dict] = deque(maxlen=200)
        self.vault_to_file: list[float] = []
        self.file_to_reload: list[float] = []
        self.next_validate = 0.0
        self.stop = threading.Event()
        self.last_status_write = 0.0
        self.previous_version = self._load_previous_version()

    # -- logging (never a value) ----------------------------------------------
    def log(self, level: str, source: str, msg: str) -> None:
        at = utcnow()
        self.log_ring.append({"at": iso(at), "level": level, "source": source, "msg": msg})
        if LEVELS[level] >= self.level:
            print(f"{iso(at)} {level:<5} [{source}] {msg}", file=self.out, flush=True)

    # -- persistence of the last seen version (non-secret) --------------------
    def _load_previous_version(self) -> int | None:
        try:
            with open(self.state_file, "rb") as handle:
                v = json.loads(handle.read(1024)).get("last_version")
            return v if isinstance(v, int) and v > 0 else None
        except (OSError, ValueError, AttributeError):
            return None

    def _save_version(self, version: int) -> None:
        self._atomic_write(self.state_file, {"last_version": version, "at": iso(utcnow())})

    @staticmethod
    def _atomic_write(path: str, doc: dict) -> None:
        directory = os.path.dirname(path) or "."
        try:
            fd, tmp = tempfile.mkstemp(dir=directory, prefix=".tmp-")
            with os.fdopen(fd, "w") as handle:
                json.dump(doc, handle)
            os.replace(tmp, path)
        except OSError:
            pass                      # status is best-effort; the process keeps serving

    # -- the door ----------------------------------------------------------------
    def check_door(self, presented: str, label: int | None) -> door_mod.Verdict:
        verdict = self.door.check(presented)
        self.last_door = {"last_verdict": verdict.verdict, "version": label, "checked_against": verdict.checked_version,
                          "at": iso(utcnow()), "simulation": True, "meaning": verdict.meaning}
        if verdict.verdict == "GRANTED":
            self.log("INFO", "secure-door", f"ACCESS GRANTED version=v{label} (fictional door: matches Vault's latest)")
        elif verdict.verdict == "DENIED":
            self.log("WARN", "secure-door",
                     f"STALE CREDENTIAL REJECTED version=v{label} (fictional door: Vault's latest is v{verdict.checked_version})")
        else:
            self.log("WARN", "secure-door", f"door unavailable: {verdict.reason}")
        return verdict

    # -- one poll --------------------------------------------------------------
    def poll_once(self) -> None:
        self.probe = health.read_probe(self.probe_file, self.probe, max(15.0, 3 * self.render_interval_s))
        self.agent = health.scan_agent_log(self.agent_log, self.agent)
        try:
            snap = snapshot.read(self.snapshot_file)
            self.snapshot_problem = None
        except snapshot.SnapshotMissing:
            snap, self.snapshot_problem = None, "no rendered snapshot yet"
        except snapshot.SnapshotInvalid as exc:
            snap = None
            if self.snapshot_problem != str(exc):
                self.log("ERROR", "consumer", f"rendered snapshot rejected: {exc} (keeping last-known-good)")
            self.snapshot_problem = str(exc)

        if snap is not None:
            if self.cached is None:
                self._first_load(snap)
            elif snap.version != self.cached.version:
                self._rotation(snap)

        now = time.monotonic()
        if self.cached is not None and now >= self.next_validate:
            self.next_validate = now + self.validate_s
            self.check_door(self.cached.value, self.cached.version)

        if now - self.last_status_write >= 1.0:
            self.write_status()

    def _first_load(self, snap: snapshot.Snapshot) -> None:
        self.log("INFO", "consumer", f"Vault Agent rendered secret available secret={self.secret}")
        prev = self.previous_version
        if prev is not None and snap.version != prev:
            missed = max(0, snap.version - prev - 1)
            self.log("WARN", "consumer",
                     f"ROTATION DETECTED v{prev} -> v{snap.version} while stopped; missed {missed} intermediate version(s)")
            self.rotations.appendleft({"from": prev, "to": snap.version, "vault_created_at": snap.created_time,
                                       "file_seen_at": None, "reloaded_at": iso(utcnow()), "missed": missed,
                                       "stale_denied": None, "fresh_granted": None, "while_stopped": True})
        self._load(snap)

    def _load(self, snap: snapshot.Snapshot) -> None:
        self.cached = snap
        self.loaded_at = utcnow()
        self.previous_version = snap.version
        self._save_version(snap.version)
        self.log("INFO", "consumer", f"credential loaded {self.secret} version=v{snap.version} fp={snap.fingerprint}")

    def _rotation(self, snap: snapshot.Snapshot) -> None:
        old = self.cached
        assert old is not None
        seen = utcnow()
        missed = max(0, snap.version - old.version - 1)
        note = f"; missed {missed} intermediate version(s)" if missed else ""
        if snap.version < old.version:
            note = "; version went backwards (secret recreated?)"
        self.log("WARN", "consumer", f"ROTATION DETECTED v{old.version} -> v{snap.version}{note}")
        stale = self.check_door(old.value, old.version)
        for _ in range(3):                         # races: another rotation between checks
            self.cached = snap
            self.loaded_at = utcnow()
            self.previous_version = snap.version
            self._save_version(snap.version)
            self.log("INFO", "consumer", f"credential reloaded version=v{snap.version} fp={snap.fingerprint}")
            fresh = self.check_door(snap.value, snap.version)
            if fresh.verdict == "GRANTED" or fresh.checked_version in (None, snap.version):
                break
            try:
                snap = snapshot.read(self.snapshot_file)
            except (snapshot.SnapshotMissing, snapshot.SnapshotInvalid):
                break
        created = parse_time(snap.created_time)
        file_at = datetime.fromtimestamp(snap.mtime, timezone.utc) if snap.mtime else None
        v2f = (file_at - created).total_seconds() if created and file_at else None
        f2r = (self.loaded_at - file_at).total_seconds() if file_at and self.loaded_at else None
        if v2f is not None and v2f >= 0:
            self.vault_to_file.append(round(v2f, 3))
        if f2r is not None and f2r >= 0:
            self.file_to_reload.append(round(f2r, 3))
        self.rotations.appendleft({
            "from": old.version, "to": snap.version, "vault_created_at": snap.created_time,
            "file_seen_at": iso(file_at), "detected_at": iso(seen), "reloaded_at": iso(self.loaded_at),
            "vault_to_file_s": v2f, "file_to_reload_s": f2r, "missed": missed,
            "stale_denied": stale.verdict == "DENIED", "fresh_granted": fresh.verdict == "GRANTED",
        })

    # -- state -----------------------------------------------------------------
    def credential_state(self) -> tuple[str, str]:
        if self.cached is None:
            return ("error", self.snapshot_problem or "") if self.snapshot_problem and self.snapshot_problem != "no rendered snapshot yet" \
                else ("no-data", self.snapshot_problem or "no rendered snapshot yet")
        if self.agent.last_error_at and (self.agent.last_refresh is None or self.agent.last_error_at > self.agent.last_refresh):
            return "stale", self.agent.last_error or "Agent reported a fetch error"
        if self.probe.state == "reachable":
            return "current", "loaded; Vault reachable"
        down_for = (utcnow() - self.probe.since).total_seconds() if self.probe.since else 0
        if self.probe.state in ("unreachable", "sealed") and down_for > self.stale_after_s:
            return "stale", f"Vault {self.probe.state} for {int(down_for)}s"
        if self.probe.state == "unknown":
            return "last-known-good", "Vault connectivity unknown"
        return "last-known-good", f"Vault {self.probe.state} since {iso(self.probe.since)}"

    @staticmethod
    def _stats(samples: list[float]) -> dict:
        if not samples:
            return {"p50": None, "max": None, "n": 0}
        return {"p50": round(statistics.median(samples), 2), "max": round(max(samples), 2), "n": len(samples)}

    def status(self) -> dict:
        state, reason = self.credential_state()
        return {
            "schema": 1,
            "secret": self.secret,
            "generated_at": iso(utcnow()),
            "agent": {
                "render_interval_s": self.render_interval_s,
                "last_change_rendered_at": iso(datetime.fromtimestamp(self.cached.mtime, timezone.utc)) if self.cached and self.cached.mtime else None,
                "last_refresh": {"observable": self.agent.observable, "at": iso(self.agent.last_refresh),
                                 "source": "agent log (template fetch success)" if self.agent.observable else None},
                "last_fetch_error": {"at": iso(self.agent.last_error_at), "what": self.agent.last_error} if self.agent.last_error_at else None,
            },
            "vault": {"probe": self.probe.state, "at": iso(self.probe.at), "since": iso(self.probe.since),
                      "detail": self.probe.detail, "meaning": "reachability only (unauthenticated status)"},
            "consumer": {
                "version": self.cached.version if self.cached else None,
                "fingerprint": self.cached.fingerprint if self.cached else None,
                "loaded_at": iso(self.loaded_at), "pid": os.getpid(), "started_at": iso(self.started_at),
                "state": state, "reason": reason, "poll_interval_s": self.poll_s, "version_impl": __version__,
            },
            "door": self.last_door,
            "latency": {"vault_to_file_s": self._stats(self.vault_to_file),
                        "file_to_reload_s": self._stats(self.file_to_reload)},
            "rotations": list(self.rotations),
            "log": list(self.log_ring),
        }

    def write_status(self) -> None:
        self._atomic_write(self.status_file, self.status())
        self.last_status_write = time.monotonic()

    def run(self) -> None:
        self.log("INFO", "consumer", f"Secure Door consumer {__version__} starting secret={self.secret} "
                                     f"poll={self.poll_s}s validate={self.validate_s}s "
                                     f"(fictional door; real Vault versions)")
        if self.previous_version:
            self.log("INFO", "consumer", f"last seen before this start: v{self.previous_version}")
        while not self.stop.is_set():
            try:
                self.poll_once()
            except Exception as exc:  # keep running; report, never swallow silently
                self.log("ERROR", "consumer", f"poll failed: {exc.__class__.__name__}")
            self.stop.wait(self.poll_s)
        self.write_status()
        self.log("INFO", "consumer", "stopped")


def main() -> None:
    consumer = Consumer()

    def _stop(*_):
        consumer.stop.set()
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    consumer.run()


if __name__ == "__main__":
    main()
