"""make rotation-consumer-test — live proof of the two-party Secure Door (prompt 01_10).

Vault-native evidence (versions, created_time and the k8s auth roles, read with
the Ansible token; pods and mounts from the API server) is kept apart from the
parties' own claims (their /status documents). Values are read into memory only
to sign test requests (the HMAC leaves this process, the value never does) and
for the leak check. They are never printed.

  run.py [--only NN]
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT / "addons/rotation/controller"))
sys.path.insert(0, str(ROOT / "addons/rotation/cli"))
sys.path.insert(0, str(ROOT / "addons/rotation/consumer/consumer"))
import rotation_cli as cli  # noqa: E402
from rotation import history as h  # noqa: E402
from rotation.vault import VaultError  # noqa: E402
from secure_door import protocol  # noqa: E402

NS = "sg-rotation-consumer"
SECRET = "api-key/secure-door"
REL = "shift-gear/rotation/api-key/secure-door"
PARTIES = ("verifier", "client")
ROLES = {"verifier": "sg-rotation-door-verifier", "client": "sg-rotation-door-client"}
TEST_CLIENT = "rotation-consumer-test"
ENV = dict(os.environ, KUBECONFIG=str(ROOT / ".secrets/kube/config"))
EVIDENCE = ROOT / ".build/addons/rotation/consumer-test.json"
GRACE = 30


def sh(*argv: str, check: bool = True, timeout: int = 900, stdin: str | None = None) -> subprocess.CompletedProcess:
    p = subprocess.run(list(argv), cwd=ROOT, env=ENV, capture_output=True, text=True, timeout=timeout, input=stdin)
    if check and p.returncode != 0:
        raise AssertionError(f"{' '.join(argv)} failed ({p.returncode}): {(p.stdout + p.stderr)[-600:]}")
    return p


def wait_for(pred, timeout: float, interval: float = 1.0, what: str = "condition"):
    end = time.time() + timeout
    while time.time() < end:
        got = pred()
        if got:
            return got
        time.sleep(interval)
    raise AssertionError(f"timed out after {timeout:.0f}s waiting for {what}")


def ts(iso: str | None) -> float | None:
    return datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp() if iso else None


def status(party: str) -> dict:
    out = sh("oc", "-n", NS, "exec", "-i", f"deploy/door-{party}", "-c", party, "--", "python3", "-", stdin=(
        "import sys,urllib.request\n"
        "sys.stdout.write(urllib.request.urlopen('http://127.0.0.1:9090/status',timeout=3).read().decode())"))
    return json.loads(out.stdout)


def body(party: str) -> dict:
    return status(party)[party]


def try_body(party: str) -> dict | None:
    try:
        return body(party)
    except (AssertionError, ValueError):
        return None


def vault_meta():
    return cli.vault_client().read_metadata(REL)


def value_of(version: int) -> str:
    return cli.vault_client().read_value(REL, version)


def tf_apply(*extra: str) -> None:
    sh("./scripts/tf-run.sh", "rotation-consumer", "apply", "-no-color", *extra)


def rollout(deploy: str) -> None:
    sh("oc", "-n", NS, "rollout", "status", f"deploy/{deploy}", "--timeout=180s")


def pod(party: str) -> dict:
    items = json.loads(sh("oc", "-n", NS, "get", "pod", "-l", f"app.kubernetes.io/name=door-{party}", "-o", "json").stdout)["items"]
    p = [i for i in items if not i["metadata"].get("deletionTimestamp")][0]
    return {"name": p["metadata"]["name"], "sa": p["spec"].get("serviceAccountName"),
            "mounts": {c["name"]: sorted(m["name"] for m in c.get("volumeMounts", [])) for c in p["spec"]["containers"]},
            "started": {c["name"]: (c.get("state", {}).get("running") or {}).get("startedAt")
                        for c in p["status"].get("containerStatuses", [])}}


def agent_log(party: str) -> str:
    return sh("oc", "-n", NS, "exec", f"deploy/door-{party}", "-c", party, "--", "cat", "/agent-log/agent.log").stdout


def verifier_clock_offset() -> float:
    """Verifier time minus local time (the CRC VM clock can drift from the Mac's)."""
    t0 = time.time()
    gen = ts(status("verifier")["generated_at"])
    return gen - (t0 + time.time()) / 2


def knock(req: dict) -> dict:
    """Send one request to the verifier from inside the client pod (the only
    pod allowed to reach /enter). The request carries an HMAC, never a value."""
    script = (
        "import json,os,urllib.request,urllib.error\n"
        f"req=urllib.request.Request(os.environ['DOOR_VERIFIER_URL'],data={json.dumps(json.dumps(req))}.encode(),"
        "method='POST',headers={'Content-Type':'application/json'})\n"
        "try:\n r=urllib.request.urlopen(req,timeout=5);print(r.status,r.read().decode())\n"
        "except urllib.error.HTTPError as e:\n print(e.code,e.read().decode())\n")
    out = sh("oc", "-n", NS, "exec", "-i", "deploy/door-client", "-c", "client", "--", "python3", "-", stdin=script).stdout
    code, _, doc = out.strip().partition(" ")
    return {"http": int(code), **json.loads(doc)}


def signed(version: int, *, age_s: float = 0, offset: float = 0.0) -> dict:
    return protocol.new_request(value_of(version), version, TEST_CLIENT, now=int(time.time() + offset - age_s))


def rotate_now(reason: str) -> int:
    before = vault_meta().current_version
    assert cli.main(["rotate", SECRET, "--reason", reason, "--wait", "45"]) == 0, "rotation request failed"
    return before


def settled(target: int):
    """Both parties hold `target` (or newer) and the client's last request was granted."""
    def check():
        v, c = try_body("verifier"), try_body("client")
        if not v or not c:
            return None
        ok = (v["current_version"] or 0) >= target and (c["version"] or 0) >= target and \
            (c.get("last") or {}).get("verdict") == "GRANTED" and c.get("open_window") is None
        return (v, c) if ok else None
    return check


def set_mode(grace: int) -> dict:
    if grace == GRACE:
        tf_apply()
    else:
        tf_apply(f"-var=grace_seconds={grace}")
    rollout("door-verifier")
    v = wait_for(lambda: (lambda b: b if b and b["grace_seconds"] == grace and b["current_version"] else None)(try_body("verifier")),
                 90, 2, f"verifier in {'strict' if grace == 0 else 'grace'} mode")
    wait_for(settled(v["current_version"]), 60, 1, "client granted after the verifier restart")
    return v


class Suite:
    def __init__(self):
        self.results: list[dict] = []
        self.changed_mode = False
        self.cut = False

    # d01 — two parties, two identities; only each Agent holds a token
    def d01_independence(self) -> dict:
        facts = {}
        for party in PARTIES:
            info = pod(party)
            assert set(info["mounts"]) == {"vault-agent", "vault-probe", party}, info["mounts"]
            holders = [c for c, m in info["mounts"].items() if "vault-token" in m]
            assert holders == ["vault-agent"], f"{party}: vault-token mounted in {holders}"
            assert info["sa"] == f"door-{party}", info["sa"]
            iso = json.loads(sh("oc", "-n", NS, "exec", "-i", f"deploy/door-{party}", "-c", party, "--", "python3", "-", stdin=(
                "import os,glob,json\n"
                "print(json.dumps({'vault_env':[k for k in os.environ if k.startswith('VAULT_')],"
                "'token_files':glob.glob('/var/run/secrets/**/token',recursive=True)}))")).stdout)
            assert not iso["vault_env"] and not iso["token_files"], (party, iso)
            log = agent_log(party)
            assert "authentication successful" in log or "received new token" in log, f"{party}: agent never authenticated"
            facts[party] = {"service_account": info["sa"], "token_only_in": holders}
        # Vault side: two roles, each bound to its own ServiceAccount and policy.
        v = cli.vault_client()
        for party, role in ROLES.items():
            data = v.request("GET", f"auth/kubernetes/role/{role}")["data"]
            assert data["bound_service_account_names"] == [f"door-{party}"], data["bound_service_account_names"]
            assert data["policies"] == [role] or data.get("token_policies") == [role], data
            facts[party]["vault_role"] = role
        assert sh("oc", "-n", NS, "get", "deploy", "secure-door", check=False).returncode != 0, "the 01_09 single pod is still there"
        return facts

    # d02 — strict mode: the verifier retires the old key at once; denials are measured
    def d02_strict(self) -> dict:
        self.changed_mode = True
        set_mode(0)
        started = (status("client")["started_at"], pod("client")["started"]["client"])
        rotations, measured = [], 0
        for i in range(8):
            before_c = body("client")
            seen_windows = {w["start"] for w in before_c["windows"]}
            fallbacks0 = before_c["outcomes"].get("fallback", 0)
            rotate_now(f"rotation-consumer-test d02 strict #{i + 1}")
            target = vault_meta().current_version
            v, c = wait_for(settled(target), 60, 1, f"both parties at v{target}, client granted")
            new = [w for w in c["windows"] if w["start"] not in seen_windows]
            adopt = next((a for a in v["adoptions"] if a["version"] == target), {})
            rel = next((r for r in c["rotations"] if r["to"] == target), {})
            created = vault_meta().created(target)
            row = {"version": target,
                   "verifier_adopted_after_s": round(ts(adopt.get("adopted_at")) - created.timestamp(), 2) if adopt else None,
                   "client_reloaded_after_s": round(ts(rel.get("reloaded_at")) - created.timestamp(), 2) if rel else None,
                   "denied": sum(w["denied"] for w in new), "windows_s": [w["seconds"] for w in new],
                   "reasons": sorted({r for w in new for r in w.get("reasons", {w["reason"]: 1})}),
                   "fallbacks": c["outcomes"].get("fallback", 0) - fallbacks0}
            if row["verifier_adopted_after_s"] is not None and row["client_reloaded_after_s"] is not None:
                row["client_minus_verifier_s"] = round(row["client_reloaded_after_s"] - row["verifier_adopted_after_s"], 2)
                # A fallback proves the client signed with a version the verifier did not know yet.
                row["first"] = "client" if row["fallbacks"] or row["client_minus_verifier_s"] < 0 else "verifier"
            rotations.append(row)
            if row["denied"]:
                measured += 1
                assert row["reasons"] == ["version-retired"], row
                assert max(row["windows_s"]) <= 20, f"unbounded window {row}"
            if measured >= 2:
                break
            time.sleep(3)
        assert measured >= 1, f"no denial window in {len(rotations)} strict rotations: {rotations}"
        assert (status("client")["started_at"], pod("client")["started"]["client"]) == started, "client process restarted"
        return {"mode": "strict", "rotations": rotations, "client_process_unchanged": started[0],
                "note": "a rotation the client's Agent delivers first is covered by the fallback to the previous key"}

    # d03 — grace mode: zero denials; old key, stale timestamp and a replay are refused
    def d03_grace(self) -> dict:
        set_mode(GRACE)
        self.changed_mode = False
        c0, v0 = body("client"), body("verifier")
        denied0, windows0 = c0["outcomes"].get("DENIED", 0), len(c0["windows"])
        grace0 = sum(n for k, n in v0["verdicts"].items() if k.startswith("GRANTED:grace"))
        old = vault_meta().current_version
        for i in range(2):
            rotate_now(f"rotation-consumer-test d03 grace #{i + 1}")
            target = vault_meta().current_version
            wait_for(settled(target), 60, 1, f"both parties at v{target}")
            time.sleep(3)
        c1, v1 = body("client"), body("verifier")
        assert c1["outcomes"].get("DENIED", 0) == denied0 and len(c1["windows"]) == windows0, \
            f"denials in grace mode: {c1['outcomes']} windows {c1['windows'][:2]}"
        grace_grants = sum(n for k, n in v1["verdicts"].items() if k.startswith("GRANTED:grace")) - grace0
        fallbacks = c1["outcomes"].get("fallback", 0) - c0["outcomes"].get("fallback", 0)

        # Old key after grace + 5 s: refused as retired.
        adopted = next(a for a in reversed(v1["adoptions"]) if a["version"] > old)
        wait_for(lambda: time.time() >= ts(adopted["adopted_at"]) + GRACE + 5 and
                 all(k["version"] > old for k in body("verifier")["ring"]), GRACE + 60, 2, f"v{old} past its grace")
        off = verifier_clock_offset()
        replay_old = knock(signed(old, offset=off))
        assert (replay_old["http"], replay_old["verdict"], replay_old["reason"]) == (403, "DENIED", "version-retired"), replay_old
        current = body("verifier")["current_version"]
        stale = knock(signed(current, age_s=60, offset=off))
        assert (stale["verdict"], stale["reason"]) == ("DENIED", "stale-timestamp"), stale
        req = signed(current, offset=off)
        first, again = knock(req), knock(dict(req))
        assert first["verdict"] == "GRANTED", first
        assert (again["verdict"], again["reason"]) == ("DENIED", "replayed-nonce"), again
        return {"mode": f"grace {GRACE}s", "rotations": f"v{old}->v{current}", "client_denials": 0,
                "granted_on_grace": grace_grants, "client_fallbacks": fallbacks,
                "old_key_after_grace": f"v{old} {replay_old['verdict']} {replay_old['reason']}",
                "timestamp_60s_old": stale["reason"], "same_request_twice": f"{first['verdict']} then {again['reason']}"}

    # d03b — a client whose Agent is cut off for longer than the grace period
    def d03b_client_late(self) -> dict:
        cv = body("client")["version"]
        self.cut = True
        sh("oc", "-n", "sg-vault", "delete", "networkpolicy", "allow-sg-rotation-door-client")
        try:
            wait_for(lambda: status("client")["vault"]["probe"] == "unreachable", 45, 1, "client probe unreachable")
            rotate_now("rotation-consumer-test d03b late client")
            v = wait_for(lambda: (lambda b: b if b["current_version"] > cv else None)(body("verifier")), 30, 1, "verifier adopted")
            adopted = ts(next(a for a in v["adoptions"] if a["version"] > cv and a["previous"] == cv)["adopted_at"])
            c = wait_for(lambda: (lambda b: b if b.get("open_window") else None)(body("client")), GRACE + 60, 1,
                         "client denied once the grace ran out")
            win = c["open_window"]
            assert win["reason"] == "version-retired" and c["version"] == cv, (win, c["version"])
            granted_for = ts(win["start"]) - adopted
            assert granted_for >= GRACE - 3, f"denied after {granted_for:.1f}s, before the grace ran out"
        finally:
            tf_apply()
            self.cut = False
        _, c = wait_for(settled(vault_meta().current_version), 90, 1, "client recovered")
        w = next(x for x in c["windows"] if x["start"] == win["start"])
        return {"client_held": f"v{cv}", "granted_on_grace_for_s": round(granted_for, 1),
                "then": f"{w['denied']} denied ({', '.join(f'{k} {n}' for k, n in w['reasons'].items())}) in {w['seconds']}s",
                "recovered_after_reapply": f"v{c['version']} granted"}

    # d05 — the client is stopped across rotations; the verifier is not interrupted
    def d05_client_restart(self) -> dict:
        vstart = status("verifier")["started_at"]
        sh("oc", "-n", NS, "scale", "deploy/door-client", "--replicas=0")
        try:
            sh("oc", "-n", NS, "wait", "--for=delete", "pod", "-l", "app.kubernetes.io/name=door-client", "--timeout=120s", check=False)
            last_seen = vault_meta().current_version
            for i in range(3):
                assert cli.main(["rotate", SECRET, "--reason", f"rotation-consumer-test d05 #{i + 1}", "--wait", "45"]) == 0
            now = vault_meta().current_version
        finally:
            sh("oc", "-n", NS, "scale", "deploy/door-client", "--replicas=1")
            rollout("door-client")
        c = wait_for(lambda: (lambda b: b if b and b["rotations"] and b["rotations"][0].get("while_stopped") else None)(try_body("client")),
                     60, 1, "gap reported after restart")
        r = c["rotations"][0]
        assert r["missed"] >= 2, r
        wait_for(settled(now), 60, 1, "client granted after restart")
        assert status("verifier")["started_at"] == vstart, "the verifier restarted"
        return {"vault": f"v{last_seen}->v{now} while the client was stopped", "client_reported": f"v{r['from']}->v{r['to']}",
                "missed": r["missed"], "verifier_process_unchanged": vstart}

    # d06 — verifier restart: the ring restarts with the current version only
    def d06_verifier_restart(self) -> dict:
        cv = body("client")["version"]
        self.cut = True
        sh("oc", "-n", "sg-vault", "delete", "networkpolicy", "allow-sg-rotation-door-client")
        try:
            wait_for(lambda: status("client")["vault"]["probe"] == "unreachable", 45, 1, "client probe unreachable")
            rotate_now("rotation-consumer-test d06 verifier restart")
            wait_for(lambda: body("verifier")["current_version"] > cv, 30, 1, "verifier adopted")
            vstart = status("verifier")["started_at"]
            sh("oc", "-n", NS, "rollout", "restart", "deploy/door-verifier")
            rollout("door-verifier")
            v = wait_for(lambda: (lambda d: d["verifier"] if d["started_at"] != vstart and d["verifier"]["current_version"] else None)(status("verifier")),
                         60, 1, "verifier back")
            ring = [k["version"] for k in v["ring"]]
            assert ring == [v["current_version"]], ring
            c = wait_for(lambda: (lambda b: b if (b.get("open_window") or {}).get("reasons", {}).get("version-retired") else None)(body("client")),
                         60, 1, "client denied: its version is not in the new ring")
            assert c["version"] == cv, c["version"]
            start = c["open_window"]["start"]
        finally:
            tf_apply()
            self.cut = False
        _, c = wait_for(settled(vault_meta().current_version), 90, 1, "client recovered")
        w = next(x for x in c["windows"] if x["start"] == start)
        return {"ring_after_restart": [f"v{x}" for x in ring], "client_held": f"v{cv}",
                "reported": f"{w['denied']} refused ({', '.join(f'{k} {n}' for k, n in w['reasons'].items())}) in {w['seconds']}s",
                "note": "grace lives in the verifier's memory: a restart forgets the previous version"}

    # d07 — the cascade: an application release rotates the door's secret
    def d07_cascade(self) -> dict:
        start = vault_meta().current_version
        t0 = datetime.now(timezone.utc)
        sh("make", "wl-a-rotate", timeout=300)
        m = wait_for(lambda: (lambda mm: mm if any(n > start and r.trigger == "event" for n, r in h.decode(mm.custom).items()) else None)(vault_meta()),
                     90, 1, "event-triggered rotation of secure-door")
        n = min(n for n, r in h.decode(m.custom).items() if n > start and r.trigger == "event")
        wait_for(settled(n), 60, 1, f"both parties at v{n}")
        return {"versions": f"v{start}->v{n}", "trigger": "event", "after_s": round((m.created(n) - t0).total_seconds(), 1)}

    # d04 — the board (Playwright + axe, 1440 and 390), while the strict windows and the
    # verifier's refusals from d02–d03b are still in both processes' memory
    def d04_board(self) -> dict:
        board = ROOT / "addons/rotation/consumer/tests/board"
        link = board / "node_modules"
        if not link.exists():
            link.symlink_to(ROOT / "ui/node_modules")
        url = json.loads((ROOT / ".build/terraform/rotation-consumer.json").read_text())["board_url"]
        p = subprocess.run(["npx", "--prefix", str(ROOT / "ui"), "playwright", "test", "-c", str(board / "playwright.config.ts")],
                           cwd=board, env=dict(ENV, SG_BOARD_URL=url), capture_output=True, text=True, timeout=900)
        summary = [l.strip() for l in p.stdout.splitlines() if l.strip().endswith(("passed", "failed")) or "passed (" in l or " failed" in l]
        assert p.returncode == 0, (p.stdout + p.stderr)[-1500:]
        return {"board_url": url, "playwright": summary[-2:] if summary else "passed"}

    # d08 — idempotent re-install; removal leaves the controller and the secret alone
    def d08_lifecycle(self) -> dict:
        before = {p: pod(p)["name"] for p in PARTIES}
        sh("make", "rotation-consumer-up")
        assert "No changes." in (ROOT / ".build/addons/rotation/consumer-tf-apply.log").read_text()
        stats = {f.stem: json.loads(f.read_text()).get("changed_total")
                 for f in (ROOT / ".build/addons/rotation/ansible-stats").glob("rotation-consumer-*.json") if "down" not in f.stem}
        assert all(v == 0 for v in stats.values()), stats
        assert {p: pod(p)["name"] for p in PARTIES} == before, "re-install restarted a party"
        meta_before = vault_meta()
        sh("make", "rotation-consumer-down")
        assert sh("oc", "get", "namespace", NS, check=False).returncode != 0, "namespace still present"
        for party in PARTIES:
            assert sh("oc", "-n", "sg-vault", "get", "networkpolicy", f"allow-sg-rotation-door-{party}", check=False).returncode != 0
        v = cli.vault_client()
        for role in ROLES.values():
            try:
                v.request("GET", f"auth/kubernetes/role/{role}")
                raise AssertionError(f"{role} still configured")
            except VaultError as exc:
                assert exc.status == 404, exc
        assert sh("oc", "get", "namespace", "sg-rotation", check=False).returncode == 0, "controller namespace touched"
        meta_after = vault_meta()
        assert meta_after.current_version >= meta_before.current_version
        kept = set(h.decode(meta_before.custom)) & set(h.decode(meta_after.custom))
        assert kept, "history records lost"
        sh("make", "rotation-consumer-up")
        return {"reinstall": "No changes, ansible changed=0, same pods", "down": "namespace, both Vault allows and both roles removed",
                "controller": "untouched", "secret_versions": f"v{meta_before.current_version}->v{meta_after.current_version} (controller kept rotating)"}

    def leak_check(self) -> dict:
        v = cli.vault_client()
        m = vault_meta()
        values = {v.read_value(REL, n) for n, i in m.versions.items() if not i.get("destroyed")}
        values.discard(None)
        hay = {}
        for party in PARTIES:
            for c in ("vault-agent", "vault-probe", party):
                p = sh("oc", "-n", NS, "logs", f"deploy/door-{party}", "-c", c, "--tail=-1", check=False)
                hay[f"logs/{party}/{c}"] = p.stdout + p.stderr
            hay[f"{party}/agent.log"] = agent_log(party)
            hay[f"{party}/status"] = json.dumps(status(party))
        p = sh("oc", "-n", NS, "logs", "deploy/door-board", "--tail=-1", check=False)
        hay["logs/board"] = p.stdout + p.stderr
        hay["board /api/state"] = sh("oc", "-n", NS, "exec", "deploy/door-board", "-c", "board", "--", "node", "-e",
                                     "fetch('http://127.0.0.1:8080/api/state').then(r=>r.text()).then(t=>process.stdout.write(t))").stdout
        state = ROOT / ".secrets/terraform/rotation-consumer/terraform.tfstate"
        hay["tfstate"] = state.read_text() if state.exists() else ""
        for f in (ROOT / ".build").rglob("*"):
            if f.is_file() and f.stat().st_size < 5_000_000:
                hay[f".build/{f.relative_to(ROOT / '.build')}"] = f.read_text(errors="ignore")
        for name in sh("git", "ls-files", "-co", "--exclude-standard", check=False).stdout.split():
            f = ROOT / name
            if f.is_file() and f.stat().st_size < 2_000_000:
                hay[f"git/{name}"] = f.read_text(errors="ignore")
        hits = sorted({w for w, t in hay.items() for val in values if val in t})
        assert not hits, f"value found in {hits}"
        return {"values_checked": len(values), "places_checked": len(hay)}

    def restore(self) -> None:
        """Leave the default layout behind, whatever failed: grace mode, both Vault allows."""
        if self.changed_mode or self.cut:
            tf_apply()


ORDER = ["d01_independence", "d02_strict", "d03_grace", "d03b_client_late", "d04_board",
         "d05_client_restart", "d06_verifier_restart", "d07_cascade", "d08_lifecycle"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only")
    args = ap.parse_args()
    chosen = [s for s in ORDER if not args.only or s.split("_")[0] in (f"d{args.only.zfill(2)}", f"d{args.only}", args.only)]
    if sh("oc", "get", "namespace", NS, check=False).returncode != 0:
        print("Secure Door not installed — make rotation-consumer-up", file=sys.stderr)
        return 2
    suite, failed = Suite(), 0
    started = datetime.now(timezone.utc)
    try:
        for name in chosen + ["leak_check"]:
            t0 = time.time()
            try:
                facts = getattr(suite, name)()
                suite.results.append({"scenario": name, "verdict": "pass", "seconds": round(time.time() - t0, 1), "facts": facts})
                print(f"  PASS  {name:<22} {time.time() - t0:6.1f}s  {json.dumps(facts)}", flush=True)
            except Exception as exc:
                failed += 1
                suite.results.append({"scenario": name, "verdict": "fail", "error": str(exc)})
                print(f"  FAIL  {name:<22} {time.time() - t0:6.1f}s  {exc}", flush=True)
                suite.restore()
    finally:
        suite.restore()
    EVIDENCE.write_text(json.dumps({"suite": "rotation-consumer-test", "started": started.isoformat(),
                                    "finished": datetime.now(timezone.utc).isoformat(), "failed": failed,
                                    "results": suite.results}, indent=2) + "\n")
    print(f"\nrotation-consumer-test: {len(suite.results) - failed} passed, {failed} failed — evidence {EVIDENCE.relative_to(ROOT)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
