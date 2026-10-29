"""make rotation-test — live proof of the KV rotation add-on.

Every assertion reads Vault's own data (versions, created_time, custom
metadata) or HTTP status codes from Vault; never only the controller's word.
The suite applies a test overlay (tests/live/rotation.test.yaml: three rt-*
secrets on a 20 s cadence, 5 s loop) and restores the normal configuration at
the end — s09 does that through `make rotation-down` + `make rotation-up`, and
a trap does it on failure. Test secrets stay in Vault (nothing in this add-on
deletes a secret); they are named rt-* and harmless.

  run.py [--only NN] [--keep-overlay]
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import traceback
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
ADDON = ROOT / "addons/rotation"
sys.path.insert(0, str(ADDON / "controller"))
sys.path.insert(0, str(ADDON / "cli"))

from rotation import history as h  # noqa: E402
from rotation.config import load  # noqa: E402
from rotation.redact import fingerprint  # noqa: E402
from rotation.vault import Vault, VaultError, iso  # noqa: E402
import rotation_cli as cli  # noqa: E402

NS = "sg-rotation"
OVERLAY = "../tests/live/rotation.test.yaml"
ENV = dict(os.environ, KUBECONFIG=str(ROOT / ".secrets/kube/config"))
# CLI calls in this suite must know the rt-* test secrets of the overlay.
os.environ["ROTATION_CONFIG_FILE"] = str(ADDON / "tests/live/rotation.test.yaml")
EVIDENCE = ROOT / ".build/addons/rotation/rotation-test.json"


# ── plumbing ─────────────────────────────────────────────────────────────────
def sh(*argv: str, check: bool = True, timeout: int = 600, quiet: bool = True) -> subprocess.CompletedProcess:
    proc = subprocess.run(list(argv), cwd=ROOT, env=ENV, capture_output=True, text=True, timeout=timeout)
    if check and proc.returncode != 0:
        tail = "\n".join((proc.stdout + proc.stderr).strip().splitlines()[-15:])
        raise AssertionError(f"command failed ({proc.returncode}): {' '.join(argv)}\n{tail}")
    if not quiet:
        print(proc.stdout, end="")
    return proc


def tf_apply(overlay: bool) -> None:
    extra = ["-var=config_file=" + OVERLAY, "-var=test_mode=true", "-var=test_pause_after_write=10"] if overlay else []
    sh("./scripts/tf-run.sh", "rotation", "apply", "-no-color", *extra, timeout=900)
    sh("oc", "-n", NS, "rollout", "status", "deploy/rotation-controller", "--timeout=180s")


def vault() -> Vault:
    return cli.vault_client()


def md(v: Vault, rel: str):
    return v.read_metadata(rel)


def wait_for(predicate, timeout: float, interval: float = 1.0, what: str = "condition"):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        last = predicate()
        if last:
            return last
        time.sleep(interval)
    raise AssertionError(f"timed out after {timeout:.0f}s waiting for {what}")


def controller_json(path: str) -> dict:
    code = f"import urllib.request,sys;sys.stdout.write(urllib.request.urlopen('http://127.0.0.1:8080{path}',timeout=5).read().decode())"
    out = sh("oc", "-n", NS, "exec", "deploy/rotation-controller", "-c", "controller", "--", "python3", "-c", code)
    return json.loads(out.stdout)


def controller_post(path: str, body: dict) -> dict:
    code = ("import sys,json,urllib.request,urllib.error;"
            f"r=urllib.request.Request('http://127.0.0.1:8080{path}',data=sys.stdin.read().encode(),"
            "headers={'Content-Type':'application/json'},method='POST')\n"
            "try:\n print(urllib.request.urlopen(r,timeout=15).read().decode())\n"
            "except urllib.error.HTTPError as e:\n print(e.read().decode())")
    proc = subprocess.run(["oc", "-n", NS, "exec", "-i", "deploy/rotation-controller", "-c", "controller", "--",
                           "python3", "-c", code], input=json.dumps(body), capture_output=True, text=True,
                          env=ENV, timeout=60)
    return json.loads(proc.stdout or "{}")


def persona_token(v: Vault, uid: str) -> str:
    passwords = v.request("GET", "kv/data/shift-gear/identity")["data"]["data"]
    anon = Vault(v.address, v.namespace, v.mount, token=None, cafile=str(ROOT / ".secrets/tls/pub/ca.pem"))
    resp = anon.request("POST", f"auth/ldap/login/{uid}", {"password": passwords[f"user_{uid}"]})
    return resp["auth"]["client_token"]


def status_of(v: Vault, method: str, path: str, token: str, body: dict | None = None,
              content_type: str = "application/json") -> int:
    try:
        v.request(method, path, body, content_type=content_type, token=token)
        return 200
    except VaultError as exc:
        return exc.status


def recorded_after(v: Vault, rel: str, start: int):
    """Metadata once a version newer than `start` exists *and* carries its record."""
    m = md(v, rel)
    return m if m and m.current_version > start and m.current_version in h.decode(m.custom) else None


def sentinel_enabled() -> bool:
    out = ROOT / ".build/terraform/rotation.json"
    return out.exists() and bool(json.loads(out.read_text()).get("sentinel_egp"))


def vault_error(v: Vault, method: str, path: str, token: str | None, body: dict | None = None,
                content_type: str = "application/json") -> tuple[int, str]:
    try:
        v.request(method, path, body, content_type=content_type, token=token)
        return 200, ""
    except VaultError as exc:
        return exc.status, " ".join(exc.errors).lower()


def identity_order() -> str:
    """The controller must learn who it is before it touches any secret."""
    logs = sh("oc", "-n", NS, "logs", "deploy/rotation-controller", "-c", "controller", "--tail=-1").stdout.splitlines()
    msgs = [json.loads(line).get("msg") for line in logs if line.startswith("{")]
    first_identity = msgs.index("identity") if "identity" in msgs else None
    writes = [i for i, m in enumerate(msgs) if m in ("onboarded", "rotated", "recovered unrecorded versions", "enforced")]
    assert first_identity is not None, "no identity line in the controller log"
    assert not writes or first_identity < writes[0], "a secret was written before the identity was established"
    return "yes"


def records(v: Vault, rel: str) -> dict[int, h.Record]:
    m = md(v, rel)
    return h.decode(m.custom) if m else {}


# ── scenarios ────────────────────────────────────────────────────────────────
class Suite:
    def __init__(self) -> None:
        self.cfg = load(ADDON / "tests/live/rotation.test.yaml")
        self.v = vault()
        self.loop = self.cfg.loop_seconds
        self.results: list[dict] = []
        self.rel = {s.id: s.rel_path for s in self.cfg.secrets}

    def r(self, sid: str) -> str:
        return self.rel[sid]

    # s01 — time-based, per-type cadence
    def s01_time(self) -> dict:
        rel = self.r("test-key/rt-time")
        start = md(self.v, rel).current_version
        wait_for(lambda: md(self.v, rel).current_version >= start + 3, 3 * 20 + 4 * self.loop + 10, 2, "three time rotations")
        m = md(self.v, rel)
        recs = h.decode(m.custom)
        new = [n for n in range(start + 1, m.current_version + 1)]
        assert all(recs[n].trigger == "time" for n in new), f"triggers {[recs[n].trigger for n in new]}"
        # Only gaps between versions written during this test: the first new version
        # follows whatever the secret held before the overlay was applied.
        gaps = [(m.created(n) - m.created(n - 1)).total_seconds() for n in new if n - 1 in new]
        assert all(20 - 1 <= g <= 20 + 2 * self.loop + 3 for g in gaps), f"cadence gaps {gaps} not ~20s"
        fps = [recs[n].fingerprint for n in range(start, m.current_version + 1) if n in recs]
        assert len(set(fps)) == len(fps), "every version must have a different fingerprint"
        # the demo api-key keeps its own (60 s) cadence alongside
        demo = md(self.v, self.r("api-key/demo"))
        return {"versions": f"v{start}->v{m.current_version}", "gaps_s": [round(g, 1) for g in gaps],
                "demo_version": demo.current_version}

    # s02 — usage-based (reads counted from the audit stream)
    def s02_usage(self) -> dict:
        rel = self.r("test-slow/rt-usage")
        start = md(self.v, rel).current_version
        for _ in range(3):
            assert self.v.read_value(rel) is not None
            time.sleep(0.3)
        m = wait_for(lambda: recorded_after(self.v, rel, start), 4 * self.loop + 25, 1, "usage rotation")
        rec = h.decode(m.custom)[m.current_version]
        assert rec.trigger == "usage", rec.trigger
        assert m.custom.get(h.READS_SINCE) == "0", m.custom.get(h.READS_SINCE)
        # the controller's own reads are not usage: nothing further happens
        time.sleep(3 * self.loop)
        assert md(self.v, rel).current_version == m.current_version, "rotated again without new reads"
        return {"versions": f"v{start}->v{m.current_version}", "trigger": rec.trigger}

    # s03 — event: human request, served exactly once
    def s03_request(self) -> dict:
        rel = self.r("test-slow/rt-usage")
        start = md(self.v, rel).current_version
        rc = cli.main(["rotate", "test-slow/rt-usage", "--reason", "rotation-test s03", "--wait", "45"])
        assert rc == 0, "CLI rotate failed"
        m = md(self.v, rel)
        rec = h.decode(m.custom)[m.current_version]
        assert rec.trigger == "request" and "kubernetes exec" in rec.actor, (rec.trigger, rec.actor)
        served = m.custom.get(h.SERVED)
        assert served and served == h.parse_request(m.custom.get(h.REQUEST))[0], "request not marked served"
        time.sleep(3 * self.loop)
        assert md(self.v, rel).current_version == m.current_version, "request served twice"
        return {"versions": f"v{start}->v{m.current_version}", "actor": rec.actor}

    # s04 — event: Vault event notification on a watched core path (cascade)
    def s04_event(self) -> dict:
        rel = self.r("test-slow/rt-event")
        start = md(self.v, rel).current_version
        mode = controller_json("/status")["controller"]["events"]
        t0 = datetime.now(timezone.utc)
        sh("make", "wl-a-rotate", timeout=300)          # the core demo action writes app-config
        m = wait_for(lambda: recorded_after(self.v, rel, start), 4 * self.loop + 20, 0.5, "cascade rotation")
        rec = h.decode(m.custom)[m.current_version]
        assert rec.trigger == "event" and "app-config" in m.custom.get(h.WATCH, ""), rec.trigger
        latency = (m.created(m.current_version) - t0).total_seconds()
        return {"versions": f"v{start}->v{m.current_version}", "mode": mode, "latency_s": round(latency, 1)}

    # s05 — enforcement layer 1: reconciliation of tampered metadata
    def s05_reconcile(self) -> dict:
        rel = self.r("test-key/rt-time")
        token = persona_token(self.v, "cleo")
        try:
            code = status_of(self.v, "PATCH", f"kv/metadata/{rel}", token,
                             {"max_versions": 99, "custom_metadata": {h.TYPE: "tampered"}},
                             "application/merge-patch+json")
        finally:
            status_of(self.v, "POST", "auth/token/revoke-self", token, {})
        if code == 403 and sentinel_enabled():
            # Layer 3 (Sentinel) prevents the tampering outright; nothing to reconcile.
            return {"operator_patch_status": code, "prevented_by": "sentinel"}
        assert code == 200, f"operator patch returned {code}"
        m = wait_for(lambda: (lambda x: x if x.max_versions == self.cfg.max_versions and x.custom.get(h.TYPE) == "test-key" else None)(md(self.v, rel)),
                     3 * self.loop + 5, 1, "reconcile")
        logs = sh("oc", "-n", NS, "logs", "deploy/rotation-controller", "-c", "controller", "--since=60s").stdout
        assert '"msg": "enforced"' in logs, "no 'enforced' log line"
        return {"max_versions": m.max_versions, "type": m.custom.get(h.TYPE), "operator_patch_status": code}

    # s06 — enforcement layer 2: ACL (Vault decides who may do what)
    def s06_acl(self) -> dict:
        rel = self.r("test-slow/rt-usage")
        out = {}
        tokens = {u: persona_token(self.v, u) for u in ("cleo", "ben", "ada", "finn")}
        try:
            out["cleo_write_value"] = status_of(self.v, "POST", f"kv/data/{rel}", tokens["cleo"], {"data": {"value": "x" * 40}})
            out["ben_patch_request"] = status_of(self.v, "PATCH", f"kv/metadata/{rel}", tokens["ben"],
                                                 {"custom_metadata": {h.REQUEST: "s06|ben|nope"}}, "application/merge-patch+json")
            out["ada_read_value"] = status_of(self.v, "GET", f"kv/data/{rel}", tokens["ada"])
            out["finn_read_history"] = status_of(self.v, "GET", f"kv/metadata/{rel}", tokens["finn"])
            out["finn_patch_request"] = status_of(self.v, "PATCH", f"kv/metadata/{rel}", tokens["finn"],
                                                  {"custom_metadata": {h.REQUEST: "s06|finn|nope"}}, "application/merge-patch+json")
            start = md(self.v, rel).current_version
            out["cleo_patch_request"] = status_of(self.v, "PATCH", f"kv/metadata/{rel}", tokens["cleo"],
                                                  {"custom_metadata": {h.REQUEST: h.encode_request(f"s06-{int(time.time())}", "cleo", "rotation-test s06")}},
                                                  "application/merge-patch+json")
        finally:
            for t in tokens.values():
                status_of(self.v, "POST", "auth/token/revoke-self", t, {})
        # ada_read_value is 200 by the *core* policy sg-engineer (create/read/update on
        # kv/data/shift-gear/*), which also covers the managed prefix. Recorded, not
        # hidden: the add-on's ACL cannot narrow a broader core grant; 01_07's
        # Sentinel EGP refuses non-controller writes.
        expected = {"cleo_write_value": 403, "ben_patch_request": 403, "ada_read_value": 200,
                    "finn_read_history": 200, "finn_patch_request": 403, "cleo_patch_request": 200}
        assert out == expected, f"got {out}, expected {expected}"
        m = wait_for(lambda: recorded_after(self.v, rel, start), 3 * self.loop + 25, 1, "cleo's request served")
        rec = h.decode(m.custom)[m.current_version]
        assert (rec.trigger, rec.actor) == ("request", "cleo"), (rec.trigger, rec.actor)
        ada = persona_token(self.v, "ada")
        try:
            ada_caps = self.v.request("POST", "sys/capabilities-self", {"paths": [f"kv/data/{rel}"]}, token=ada)
        finally:
            status_of(self.v, "POST", "auth/token/revoke-self", ada, {})
        out["engineer_can_write_value"] = sorted((ada_caps.get("data") or ada_caps).get(f"kv/data/{rel}", []))
        root = cli.vault_client()
        root.namespace = ""            # tool tokens live in the root namespace
        caps = root.request("POST", "sys/capabilities-self", {"paths": [f"shift-gear/kv/data/{rel}"]})
        # Recorded, not asserted: the platform automation token may still write a
        # managed value here; 01_07's Sentinel EGP closes that gap.
        out["ansible_platform_can_write_value"] = sorted((caps.get("data") or caps).get(f"shift-gear/kv/data/{rel}", []))
        return out

    # s07 — compliance reporting, honest while the controller is down
    def s07_compliance(self) -> dict:
        before = cli.main(["report"])
        sh("oc", "-n", NS, "scale", "deploy/rotation-controller", "--replicas=0")
        try:
            sh("oc", "-n", NS, "wait", "--for=delete", "pod", "-l", "app.kubernetes.io/name=rotation-controller", "--timeout=120s", check=False)
            time.sleep(50)                                  # past test-key max_age (45 s)
            down_rc = cli.main(["report"])
            report = json.loads((ROOT / ".build/addons/rotation/compliance.json").read_text())
            overdue = [r["secret"] for r in report["secrets"] if any(x.startswith("overdue") for x in r["reasons"])]
            assert down_rc == 1 and "test-key/rt-time" in overdue, f"rc={down_rc} overdue={overdue}"
        finally:
            sh("oc", "-n", NS, "scale", "deploy/rotation-controller", "--replicas=1")
            sh("oc", "-n", NS, "rollout", "status", "deploy/rotation-controller", "--timeout=180s")
        def healthy():
            rep = [s for s in json.loads(json.dumps(controller_json("/compliance")))["secrets"] if s["secret"] == "test-key/rt-time"]
            return rep and rep[0]["compliant"]
        wait_for(healthy, 4 * self.loop + 30, 2, "rt-time compliant again")
        return {"healthy_report_rc": before, "down_report_rc": down_rc, "overdue_while_down": overdue}

    # s08 — crash between write and record: never a gap or a duplicate.
    # rt-usage is the one secret with the 8 s test pause between write and record.
    def s08_crash(self) -> dict:
        rel = self.r("test-slow/rt-usage")
        cli.request_via_controller("test-slow/rt-usage", "rotation-test s08", "crash window")
        def unrecorded():
            m = md(self.v, rel)
            return m if m.current_version not in h.decode(m.custom) else None
        m = wait_for(unrecorded, 3 * self.loop + 10, 0.3, "a write inside the crash window")
        crashed_at = m.current_version
        sh("oc", "-n", NS, "delete", "pod", "-l", "app.kubernetes.io/name=rotation-controller", "--wait=false")
        sh("oc", "-n", NS, "rollout", "status", "deploy/rotation-controller", "--timeout=180s")
        rec = wait_for(lambda: h.decode(md(self.v, rel).custom).get(crashed_at), 60, 1, "recovered record")
        assert rec.trigger == "recovered", rec.trigger
        m = md(self.v, rel)
        assert rec.fingerprint == fingerprint(self.v.read_value(rel, crashed_at)), "recovered fingerprint mismatch"
        versions = sorted(m.versions)
        assert versions == list(range(versions[0], versions[-1] + 1)), f"gap in versions {versions}"
        return {"crashed_at": f"v{crashed_at}", "recorded_as": rec.trigger}

    # s09 — remove and re-add: secrets and history survive, rotation resumes
    def s09_remove_readd(self) -> dict:
        snap = {sid: md(self.v, rel) for sid, rel in self.rel.items()}
        sh("make", "rotation-down", timeout=900)
        assert sh("oc", "get", "namespace", NS, check=False).returncode != 0, "namespace still present"
        for sid, rel in self.rel.items():
            after = md(self.v, rel)
            assert after.current_version == snap[sid].current_version, f"{sid} changed while removed"
            assert h.decode(after.custom) == h.decode(snap[sid].custom), f"{sid} history changed while removed"
        for root in ("foundation", "platform"):
            sh("./scripts/tf-run.sh", root, "drift", "-no-color")
        sh("make", "rotation-up", timeout=900)
        demo = self.r("api-key/demo")
        m = wait_for(lambda: (lambda x: x if x.current_version > snap["api-key/demo"].current_version else None)(md(self.v, demo)),
                     60 + 30, 2, "rotation to resume")
        versions = sorted(m.versions)
        assert versions == list(range(versions[0], versions[-1] + 1)), f"gap in versions {versions}"
        order = identity_order()
        return {"demo": f"v{snap['api-key/demo'].current_version}->v{m.current_version}", "history_kept": True,
                "identity_before_first_write": order}

    # s10 — a watched path written while the controller is offline still triggers
    def s10_offline_event(self) -> dict:
        rel = self.r("test-slow/rt-event")
        start = md(self.v, rel).current_version
        sh("oc", "-n", NS, "scale", "deploy/rotation-controller", "--replicas=0")
        try:
            sh("oc", "-n", NS, "wait", "--for=delete", "pod", "-l", "app.kubernetes.io/name=rotation-controller",
               "--timeout=120s", check=False)
            sh("make", "wl-a-rotate", timeout=300)          # written while nobody listens for events
            time.sleep(3)
            assert md(self.v, rel).current_version == start, "rotated while the controller was down?"
        finally:
            sh("oc", "-n", NS, "scale", "deploy/rotation-controller", "--replicas=1")
            sh("oc", "-n", NS, "rollout", "status", "deploy/rotation-controller", "--timeout=180s")
        ready = time.time()
        m = wait_for(lambda: recorded_after(self.v, rel, start), 2 * self.loop + 20, 0.5, "offline change detected")
        rec = h.decode(m.custom)[m.current_version]
        assert rec.trigger == "event", rec.trigger
        return {"versions": f"v{start}->v{m.current_version}", "detected_after_ready_s": round(time.time() - ready, 1)}

    # s12 — enforcement layer 3: the Sentinel EGP (ADR D18)
    def s12_sentinel(self) -> dict:
        if not sentinel_enabled():
            return {"skipped": "Sentinel layer not enabled (sentinel_enabled=false)"}
        rel = self.r("test-key/rt-time")
        current = md(self.v, rel).current_version
        out: dict = {}
        # the platform automation token: broad KV rights, refused here
        code, err = vault_error(self.v, "POST", f"kv/data/{rel}", None,
                                {"options": {"cas": current}, "data": {"value": "A" * 40}})
        out["ansible_platform_write"] = code
        assert code == 403 and ("sentinel" in err or "egp" in err or "policy" in err), (code, err)
        tokens = {u: persona_token(self.v, u) for u in ("ada", "cleo")}
        try:
            out["engineer_write"] = status_of(self.v, "POST", f"kv/data/{rel}", tokens["ada"],
                                              {"options": {"cas": current}, "data": {"value": "B" * 40}})
            out["operator_tamper_settings"] = status_of(self.v, "PATCH", f"kv/metadata/{rel}", tokens["cleo"],
                                                        {"max_versions": 99}, "application/merge-patch+json")
            out["operator_extra_key"] = status_of(self.v, "PATCH", f"kv/metadata/{rel}", tokens["cleo"],
                                                  {"custom_metadata": {h.REQUEST: "s12|cleo|x", h.TYPE: "tampered"}},
                                                  "application/merge-patch+json")
            start = md(self.v, rel).current_version
            out["operator_request"] = status_of(self.v, "PATCH", f"kv/metadata/{rel}", tokens["cleo"],
                                                {"custom_metadata": {h.REQUEST: h.encode_request(f"s12-{int(time.time())}", "cleo", "rotation-test s12")}},
                                                "application/merge-patch+json")
        finally:
            for t in tokens.values():
                status_of(self.v, "POST", "auth/token/revoke-self", t, {})
        expected = {"ansible_platform_write": 403, "engineer_write": 403, "operator_tamper_settings": 403,
                    "operator_extra_key": 403, "operator_request": 200}
        assert out == expected, f"got {out}, expected {expected}"
        # the controller itself is held to the type policy: a too-short value is refused
        short = controller_post("/test/short-write", {"secret": "test-key/rt-time"})
        out["controller_short_value"] = short.get("status")
        assert short.get("status") == 403, short
        m = wait_for(lambda: recorded_after(self.v, rel, start), 3 * self.loop + 25, 1, "normal rotations continue")
        out["rotations_continue"] = f"v{start}->v{m.current_version}"
        return out

    # s11 — a second deployment changes nothing and does not restart the controller
    def s11_idempotent_redeploy(self) -> dict:
        def pod():
            out = sh("oc", "-n", NS, "get", "pod", "-l", "app.kubernetes.io/name=rotation-controller",
                     "-o", "jsonpath={.items[0].metadata.name} {.items[0].status.startTime}").stdout.strip()
            return out
        before = pod()
        sh("make", "rotation-up", timeout=900)
        tf_log = (ROOT / ".build/addons/rotation/tf-apply.log").read_text()
        assert "No changes." in tf_log, "terraform reported changes on a second rotation-up"
        stats = {}
        for f in sorted((ROOT / ".build/addons/rotation/ansible-stats").glob("rotation-*.json")):
            if f.stem == "rotation-down":
                continue
            stats[f.stem] = json.loads(f.read_text()).get("changed_total")
        assert all(v == 0 for v in stats.values()), f"ansible changed on redeploy: {stats}"
        after = pod()
        assert before == after, f"controller pod restarted: {before} -> {after}"
        return {"terraform": "No changes", "ansible_changed": stats, "pod_unchanged": True}

    # leak check — values never leave Vault except to an authorised reader
    def leak_check(self) -> dict:
        values = set()
        for rel in self.rel.values():
            m = md(self.v, rel)
            for n, info in m.versions.items():
                if not info.get("destroyed"):
                    val = self.v.read_value(rel, n)
                    if val:
                        values.add(val)
        haystacks = {}
        for container in ("controller", "vault-agent", "vault-events"):
            p = sh("oc", "-n", NS, "logs", "deploy/rotation-controller", "-c", container, "--tail=-1", check=False)
            haystacks[f"logs/{container}"] = p.stdout + p.stderr
        haystacks["/status"] = json.dumps(controller_json("/status"))
        haystacks["/compliance"] = json.dumps(controller_json("/compliance"))
        state = ROOT / ".secrets/terraform/rotation/terraform.tfstate"
        haystacks["tfstate"] = state.read_text() if state.exists() else ""
        for f in (ROOT / ".build").rglob("*"):
            if f.is_file() and f.stat().st_size < 5_000_000:
                try:
                    haystacks[f".build/{f.relative_to(ROOT / '.build')}"] = f.read_text(errors="ignore")
                except OSError:
                    pass
        git = sh("git", "ls-files", "-co", "--exclude-standard", check=False).stdout.split()
        for name in git:
            f = ROOT / name
            if f.is_file() and f.stat().st_size < 2_000_000:
                haystacks[f"git/{name}"] = f.read_text(errors="ignore")
        hits = sorted({where for where, text in haystacks.items() for val in values if val in text})
        assert not hits, f"secret value found in: {hits}"
        return {"values_checked": len(values), "places_checked": len(haystacks)}


SCENARIOS = ["s01_time", "s02_usage", "s03_request", "s04_event", "s05_reconcile",
             "s06_acl", "s07_compliance", "s08_crash", "s10_offline_event", "s12_sentinel",
             "s09_remove_readd", "s11_idempotent_redeploy"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="run one scenario, e.g. 04")
    ap.add_argument("--keep-overlay", action="store_true")
    args = ap.parse_args()
    chosen = [s for s in SCENARIOS if not args.only or s.startswith(f"s{args.only.zfill(2)}")]
    if not chosen:
        print(f"unknown scenario {args.only}", file=sys.stderr)
        return 2
    if sh("oc", "get", "namespace", NS, check=False).returncode != 0:
        print("KV rotation add-on not installed — run make rotation-up first", file=sys.stderr)
        return 2

    started = datetime.now(timezone.utc)
    print("==> applying the rotation-test overlay (rt-* secrets, 20 s cadence, 5 s loop, test hooks)")
    tf_apply(overlay=True)
    suite = Suite()
    wait_for(lambda: all(md(suite.v, suite.r(s)) for s in ("test-key/rt-time", "test-slow/rt-usage", "test-slow/rt-event")),
             60, 2, "rt-* secrets onboarded")
    restored = False
    failed = 0
    try:
        for name in chosen:
            t0 = time.time()
            try:
                facts = getattr(suite, name)()
                suite.results.append({"scenario": name, "verdict": "pass", "seconds": round(time.time() - t0, 1), "facts": facts})
                print(f"  PASS  {name:<20} {time.time() - t0:5.1f}s  {json.dumps(facts)}")
            except Exception as exc:  # report every scenario; fail at the end
                failed += 1
                suite.results.append({"scenario": name, "verdict": "fail", "seconds": round(time.time() - t0, 1), "error": str(exc)})
                print(f"  FAIL  {name:<20} {time.time() - t0:5.1f}s  {exc}")
                if os.environ.get("ROTATION_TEST_DEBUG"):
                    traceback.print_exc()
            if name == "s09_remove_readd":
                restored = True
        try:
            facts = suite.leak_check()
            print(f"  PASS  {'leak_check':<20} {json.dumps(facts)}")
            suite.results.append({"scenario": "leak_check", "verdict": "pass", "facts": facts})
        except Exception as exc:
            failed += 1
            print(f"  FAIL  {'leak_check':<20} {exc}")
            suite.results.append({"scenario": "leak_check", "verdict": "fail", "error": str(exc)})
    finally:
        if not restored and not args.keep_overlay:
            print("==> restoring the normal configuration")
            tf_apply(overlay=False)

    run = json.loads((ROOT / ".build/run.json").read_text()) if (ROOT / ".build/run.json").exists() else {}
    EVIDENCE.parent.mkdir(parents=True, exist_ok=True)
    EVIDENCE.write_text(json.dumps({
        "suite": "rotation-test", "started": iso(started), "finished": iso(datetime.now(timezone.utc)),
        "run_id": run.get("run_id"), "cluster_id": run.get("cluster_id"),
        "passed": sum(r["verdict"] == "pass" for r in suite.results), "failed": failed,
        "results": suite.results,
    }, indent=2) + "\n")
    print(f"\nrotation-test: {sum(r['verdict'] == 'pass' for r in suite.results)} passed, {failed} failed "
          f"— evidence {EVIDENCE.relative_to(ROOT)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
