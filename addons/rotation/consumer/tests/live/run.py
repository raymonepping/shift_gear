"""make rotation-consumer-test — live proof of the Secure Door consumer (prompt 01_09).

Vault-native evidence (versions and created_time read with the Ansible token,
pod/container metadata from the API server) is kept apart from the consumer's
own claims (its status document). Values are read into memory only for the
leak check and are never printed.

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
import rotation_cli as cli  # noqa: E402
from rotation import history as h  # noqa: E402

NS = "sg-rotation-consumer"
SECRET = "api-key/secure-door"
REL = "shift-gear/rotation/api-key/secure-door"
ENV = dict(os.environ, KUBECONFIG=str(ROOT / ".secrets/kube/config"))
EVIDENCE = ROOT / ".build/addons/rotation/consumer-test.json"


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


def status() -> dict:
    out = sh("oc", "-n", NS, "exec", "-i", "deploy/secure-door", "-c", "consumer", "--", "python3", "-",
             stdin="import sys;sys.stdout.write(open('/status/state.json').read())")
    return json.loads(out.stdout)


def vault_meta():
    return cli.vault_client().read_metadata(REL)


def pod_info() -> dict:
    pod = json.loads(sh("oc", "-n", NS, "get", "pod", "-l", "app.kubernetes.io/name=secure-door", "-o", "json").stdout)["items"]
    pod = [p for p in pod if not p["metadata"].get("deletionTimestamp")][0]
    started = {c["name"]: (c.get("state", {}).get("running") or {}).get("startedAt") for c in pod["status"].get("containerStatuses", [])}
    restarts = {c["name"]: c.get("restartCount") for c in pod["status"].get("containerStatuses", [])}
    return {"pod": pod["metadata"]["name"], "started": started, "restarts": restarts}


def agent_log() -> str:
    return sh("oc", "-n", NS, "exec", "deploy/secure-door", "-c", "consumer", "--", "cat", "/agent-log/agent.log").stdout


def rotate_now(reason: str) -> int:
    before = vault_meta().current_version
    assert cli.main(["rotate", SECRET, "--reason", reason, "--wait", "45"]) == 0, "rotation request failed"
    return before


class Suite:
    def __init__(self):
        self.results: list[dict] = []

    # c01 — only the Agent does Vault work
    def c01_isolation(self) -> dict:
        info = pod_info()
        assert set(info["started"]) == {"vault-agent", "vault-probe", "consumer", "board"}, info["started"]
        check = sh("oc", "-n", NS, "exec", "-i", "deploy/secure-door", "-c", "consumer", "--", "python3", "-", stdin=(
            "import os,glob,json\n"
            "print(json.dumps({'vault_env':[k for k in os.environ if k.startswith('VAULT_')],"
            "'token_files':glob.glob('/var/run/secrets/**/token',recursive=True)+glob.glob('/agent-sink/*'),"
            "'mounts':sorted(l.split()[1] for l in open('/proc/mounts') if l.split()[1].startswith(('/vault','/var/run/secrets','/agent','/health','/status','/state')))}))")).stdout
        iso = json.loads(check)
        assert not iso["vault_env"] and not iso["token_files"], iso
        assert "/var/run/secrets/vault-token" not in iso["mounts"], iso["mounts"]
        log = agent_log()
        assert "authentication successful" in log or "received new token" in log, "agent never authenticated"
        probe = wait_for(lambda: (lambda x: x if x["vault"]["probe"] == "reachable" else None)(status()), 30, 1,
                         "the connectivity probe to report reachable (baseline)")["vault"]
        code = "".join(p.read_text() for p in (ROOT / "addons/rotation/consumer/consumer/secure_door").glob("*.py"))
        assert "urllib.request" not in code and "http.client" not in code, "consumer code makes HTTP calls"
        # Limitation, recorded: NetworkPolicies are pod-scoped, so the consumer *could* open a
        # TCP connection to Vault; it holds no token, which is the isolation that matters.
        reach = sh("oc", "-n", NS, "exec", "-i", "deploy/secure-door", "-c", "consumer", "--", "python3", "-", stdin=(
            "import socket\ntry:\n socket.create_connection(('vault-active.sg-vault.svc',8200),3).close();print('reachable')\n"
            "except OSError:\n print('unreachable')")).stdout.strip()
        return {"containers": sorted(info["started"]), "probe": probe["probe"], "consumer_vault_env": [], "consumer_token_files": [],
                "agent_authenticated": True, "consumer_tcp_to_vault": reach + " (pod-scoped NetworkPolicy; no token held)"}

    # c02 — several real rotations, no restart, measured latency, accepted interval
    def c02_hot_reload(self) -> dict:
        before_pod = pod_info()
        pid0 = status()["consumer"]["pid"]
        start = vault_meta().current_version
        rotate_now("rotation-consumer-test c02 #1")
        rotate_now("rotation-consumer-test c02 #2")
        target = start + 4
        wait_for(lambda: vault_meta().current_version >= target, 150, 3, "two scheduled rotations as well")
        m = vault_meta()
        s = wait_for(lambda: (lambda x: x if x["consumer"]["version"] == vault_meta().current_version else None)(status()),
                     30, 1, "consumer at Vault's current version")
        after_pod = pod_info()
        assert s["consumer"]["pid"] == pid0, "consumer process restarted"
        assert after_pod["pod"] == before_pod["pod"] and after_pod["started"]["consumer"] == before_pod["started"]["consumer"], \
            "consumer container restarted"
        seen = [r for r in s["rotations"] if r["to"] > start]
        assert len({r["to"] for r in seen}) >= 3, f"consumer observed only {[r['to'] for r in seen]}"
        # The Agent's accepted interval: successful fetches in its log over a 30 s window.
        t0 = agent_log().count("successful data response")
        time.sleep(30)
        fetches = agent_log().count("successful data response") - t0
        lat = s["latency"]
        return {"vault_versions": f"v{start}->v{m.current_version}", "observed": sorted({r["to"] for r in seen}),
                "pid_unchanged": True, "container_unchanged": True,
                "agent_fetches_per_30s": fetches, "effective_interval_s": round(30 / fetches, 1) if fetches else None,
                "vault_to_file_s": lat["vault_to_file_s"], "file_to_reload_s": lat["file_to_reload_s"]}

    # c03 — the door's stale-then-fresh sequence, against the independent snapshot
    def c03_door(self) -> dict:
        start = vault_meta().current_version
        rotate_now("rotation-consumer-test c03")
        s = wait_for(lambda: (lambda x: x if any(r["to"] > start for r in x["rotations"]) else None)(status()), 30, 1, "rotation seen")
        r = next(r for r in s["rotations"] if r["to"] > start)
        assert r["stale_denied"] is True and r["fresh_granted"] is True, r
        lines = [l["msg"] for l in s["log"]]
        assert any(f"STALE CREDENTIAL REJECTED version=v{r['from']}" in m for m in lines), "no stale rejection logged"
        assert any(f"ACCESS GRANTED version=v{r['to']}" in m for m in lines), "no fresh grant logged"
        assert s["door"]["simulation"] is True and "no issuer exists" in s["door"]["meaning"]
        return {"rotation": f"v{r['from']}->v{r['to']}", "stale": "DENIED", "fresh": "GRANTED",
                "door_checked_against": s["door"].get("checked_against")}

    # c04 — Vault becomes unreachable for this pod; honest states; recovery
    def c04_connectivity(self) -> dict:
        # Stable baseline: unchanged secret + reachable Vault must never read stale.
        samples = [status()["consumer"]["state"] for _ in range(6) if not time.sleep(2)]
        assert set(samples) == {"current"}, f"not steady current while reachable: {samples}"
        refresh_before = status()["agent"]["last_refresh"]["at"]
        t_cut = time.time()
        sh("oc", "-n", "sg-vault", "delete", "networkpolicy", "allow-sg-rotation-consumer")
        try:
            s = wait_for(lambda: (lambda x: x if x["vault"]["probe"] == "unreachable" else None)(status()), 45, 1, "probe unreachable")
            t_unreach = time.time() - t_cut
            assert s["consumer"]["state"] == "last-known-good", s["consumer"]
            s = wait_for(lambda: (lambda x: x if x["consumer"]["state"] == "stale" else None)(status()), 120, 2, "stale after threshold")
            t_stale = time.time() - t_cut
            refresh_during = s["agent"]["last_refresh"]["at"]
        finally:
            sh("./scripts/tf-run.sh", "rotation-consumer", "apply", "-no-color")
        t_fix = time.time()
        s = wait_for(lambda: (lambda x: x if x["consumer"]["state"] == "current" else None)(status()), 90, 1, "current again")
        return {"unreachable_after_s": round(t_unreach, 1), "stale_after_s": round(t_stale, 1),
                "recovered_after_reapply_s": round(time.time() - t_fix, 1),
                "refresh_before_cut": refresh_before, "last_refresh_while_cut": refresh_during,
                "note": "a refresh after the cut would mean an established Agent connection survived the policy change"}

    # c05 — the consumer is stopped across rotations; it reports the gap on restart
    def c05_missed(self) -> dict:
        sh("oc", "-n", NS, "scale", "deploy/secure-door", "--replicas=0")
        try:
            sh("oc", "-n", NS, "wait", "--for=delete", "pod", "-l", "app.kubernetes.io/name=secure-door", "--timeout=120s", check=False)
            last_seen = vault_meta().current_version
            for i in range(3):
                assert cli.main(["rotate", SECRET, "--reason", f"rotation-consumer-test c05 #{i + 1}", "--wait", "45"]) == 0
            now = vault_meta().current_version
        finally:
            sh("oc", "-n", NS, "scale", "deploy/secure-door", "--replicas=1")
            sh("oc", "-n", NS, "rollout", "status", "deploy/secure-door", "--timeout=180s")
        s = wait_for(lambda: (lambda x: x if x["rotations"] and x["rotations"][0].get("while_stopped") else None)(status()),
                     60, 1, "gap reported after restart")
        r = s["rotations"][0]
        assert r["missed"] >= 2, r
        return {"vault": f"v{last_seen}->v{now} while stopped", "consumer_reported": f"v{r['from']}->v{r['to']}",
                "missed": r["missed"]}

    # c06 — idempotent re-install; removal leaves the controller and the secret alone
    def c06_lifecycle(self) -> dict:
        before = pod_info()
        sh("make", "rotation-consumer-up")
        assert "No changes." in (ROOT / ".build/addons/rotation/consumer-tf-apply.log").read_text()
        stats = {f.stem: json.loads(f.read_text()).get("changed_total")
                 for f in (ROOT / ".build/addons/rotation/ansible-stats").glob("rotation-consumer-*.json") if "down" not in f.stem}
        assert all(v == 0 for v in stats.values()), stats
        assert pod_info()["pod"] == before["pod"], "re-install restarted the pod"
        meta_before = vault_meta()
        sh("make", "rotation-consumer-down")
        assert sh("oc", "get", "namespace", NS, check=False).returncode != 0, "namespace still present"
        assert sh("oc", "-n", "sg-vault", "get", "networkpolicy", "allow-sg-rotation-consumer", check=False).returncode != 0
        assert sh("oc", "get", "namespace", "sg-rotation", check=False).returncode == 0, "controller namespace touched"
        meta_after = vault_meta()
        assert meta_after.current_version >= meta_before.current_version
        kept = set(h.decode(meta_before.custom)) & set(h.decode(meta_after.custom))
        assert kept, "history records lost"
        sh("make", "rotation-consumer-up")
        return {"reinstall": "No changes, ansible changed=0, same pod", "down": "namespace and Vault allow removed",
                "controller": "untouched", "secret_versions": f"v{meta_before.current_version}->v{meta_after.current_version} (controller kept rotating)"}

    # c07 — the board (Playwright + axe, 1440 and 390), against the live consumer
    def c07_board(self) -> dict:
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

    def leak_check(self) -> dict:
        v = cli.vault_client()
        m = vault_meta()
        values = {v.read_value(REL, n) for n, i in m.versions.items() if not i.get("destroyed")}
        values.discard(None)
        hay = {}
        for c in ("vault-agent", "vault-probe", "consumer", "board"):
            p = sh("oc", "-n", NS, "logs", "deploy/secure-door", "-c", c, "--tail=-1", check=False)
            hay[f"logs/{c}"] = p.stdout + p.stderr
        hay["agent.log"] = agent_log()
        hay["state.json"] = json.dumps(status())
        hay["board /api/state"] = sh("oc", "-n", NS, "exec", "deploy/secure-door", "-c", "board", "--", "node", "-e",
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


ORDER = ["c01_isolation", "c02_hot_reload", "c03_door", "c04_connectivity", "c05_missed", "c06_lifecycle", "c07_board"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only")
    args = ap.parse_args()
    chosen = [s for s in ORDER if not args.only or s.startswith(f"c{args.only.zfill(2)}")]
    if sh("oc", "get", "namespace", NS, check=False).returncode != 0:
        print("Secure Door consumer not installed — make rotation-consumer-up", file=sys.stderr)
        return 2
    suite, failed = Suite(), 0
    started = datetime.now(timezone.utc)
    for name in chosen + ["leak_check"]:
        t0 = time.time()
        try:
            facts = getattr(suite, name)()
            suite.results.append({"scenario": name, "verdict": "pass", "seconds": round(time.time() - t0, 1), "facts": facts})
            print(f"  PASS  {name:<18} {time.time() - t0:6.1f}s  {json.dumps(facts)}", flush=True)
        except Exception as exc:
            failed += 1
            suite.results.append({"scenario": name, "verdict": "fail", "error": str(exc)})
            print(f"  FAIL  {name:<18} {time.time() - t0:6.1f}s  {exc}", flush=True)
    EVIDENCE.write_text(json.dumps({"suite": "rotation-consumer-test", "started": started.isoformat(),
                                    "finished": datetime.now(timezone.utc).isoformat(), "failed": failed,
                                    "results": suite.results}, indent=2) + "\n")
    print(f"\nrotation-consumer-test: {len(suite.results) - failed} passed, {failed} failed — evidence {EVIDENCE.relative_to(ROOT)}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
