"""Host CLI for the KV rotation add-on: status, history, rotate, read, report.

Reads Vault directly (Route + project CA). Works whether or not the
controller runs, so `report` stays honest during an outage. Tokens are read
from .secrets/tokens/ and never printed.

  status                       every managed secret: version, fingerprint, trigger, next due, compliance
  history SECRET [--reveal]    v1 -> vN with fingerprints (values only with --reveal / REVEAL=1 on a TTY)
  rotate SECRET [--reason R]   request a rotation (event trigger) and wait for the new version
  read SECRET                  one read of the value (usage demo) — prints the fingerprint only
  report                       compliance table + .build/addons/rotation/compliance.{json,md}

Exit codes: 0 ok, 1 non-compliant / failed, 2 not configured.
"""
from __future__ import annotations

import argparse
import getpass
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "addons/rotation/controller"))

from rotation import compliance, history as h, triggers  # noqa: E402
from rotation.config import ConfigError, load  # noqa: E402
from rotation.redact import fingerprint  # noqa: E402
from rotation.vault import Vault, VaultError, Unreachable, iso  # noqa: E402

NAMESPACE = "shift-gear"
BUILD = ROOT / ".build/addons/rotation"


def now() -> datetime:
    return datetime.now(timezone.utc)


def vault_client(token_name: str = "ansible-platform") -> Vault:
    infra = json.loads((ROOT / ".build/terraform/infra.json").read_text())
    domain = infra["cluster"]["apps_domain"]
    token = (ROOT / ".secrets/tokens" / token_name).read_text().strip()
    return Vault(f"https://vault.{domain}", NAMESPACE, "kv", token=token,
                 cafile=str(ROOT / ".secrets/tls/pub/ca.pem"))


def config():
    return load(os.environ.get("ROTATION_CONFIG_FILE", ROOT / "addons/rotation/rotation.yaml"))


def ago(moment: datetime | None) -> str:
    if moment is None:
        return "-"
    seconds = int((now() - moment).total_seconds())
    for unit, size in (("d", 86400), ("h", 3600), ("m", 60)):
        if seconds >= size:
            return f"{seconds // size}{unit} ago"
    return f"{seconds}s ago"


def table(rows: list[list[str]], header: list[str]) -> str:
    widths = [max(len(str(r[i])) for r in [header] + rows) for i in range(len(header))]
    line = lambda r: "  ".join(str(c).ljust(w) for c, w in zip(r, widths)).rstrip()  # noqa: E731
    return "\n".join([line(header)] + [line(r) for r in rows])


def cmd_status(args) -> int:
    cfg, vault = config(), vault_client()
    rows, bad = [], 0
    for secret in cfg.secrets:
        md = vault.read_metadata(secret.rel_path)
        result = compliance.evaluate(secret, cfg, md, now())
        bad += not result["compliant"]
        if md is None:
            rows.append([secret.id, secret.owner, "-", "-", "-", "-", "-", "NOT ONBOARDED"])
            continue
        state = triggers.State(md.created(md.current_version), None)
        due = triggers.next_due(secret, state).get("time")
        due_text = "-" if due is None else (
            "due now" if due <= time.time() else f"in {int(due - time.time())}s")
        rows.append([secret.id, secret.owner, f"v{md.current_version}", result.get("fingerprint") or "?",
                     ago(md.created(md.current_version)), md.custom.get(h.LAST_TRIGGER, "-"), due_text,
                     "COMPLIANT" if result["compliant"] else "NON-COMPLIANT"])
    print(table(rows, ["SECRET", "OWNER", "VERSION", "FINGERPRINT", "LAST ROTATED", "TRIGGER", "NEXT (TIME)", "STATUS"]))
    return 1 if bad else 0


def cmd_history(args) -> int:
    cfg, vault = config(), vault_client()
    secret = cfg.secret(args.secret)
    md = vault.read_metadata(secret.rel_path)
    if md is None:
        print(f"{secret.id}: not onboarded yet")
        return 1
    reveal = args.reveal or os.environ.get("REVEAL") == "1"
    if reveal and not (sys.stdout.isatty() or os.environ.get("REVEAL") == "1"):
        print("refusing to reveal values when stdout is not a terminal (set REVEAL=1 to insist)", file=sys.stderr)
        return 1
    records = h.decode(md.custom)
    print(f"{cfg.mount}/{secret.rel_path}  ({secret.type.name}; strategies: {', '.join(secret.strategies)}; "
          f"keeps {md.max_versions} versions)")
    if reveal:
        print("WARNING: printing secret values to this terminal (demo only)")
    rows = []
    for version in sorted(md.versions, reverse=True):
        rec = records.get(version)
        info = md.versions[version]
        value = "-"
        if reveal and not info.get("destroyed"):
            value = vault.read_value(secret.rel_path, version) or "-"
        event = "Created" if rec and rec.trigger == "created" else (
            f"Rotated ({rec.trigger})" if rec else "Unrecorded")
        actor = rec.actor if rec else "-"
        row = [f"v{version}", rec.fingerprint if rec else "?", event, actor, iso(md.created(version)) if md.created(version) else "-"]
        if reveal:
            row.insert(2, value)
        rows.append(row)
    header = ["VERSION", "FINGERPRINT", "EVENT", "ACTOR", "AT"]
    if reveal:
        header.insert(2, "VALUE")
    print(table(rows, header))
    oldest = md.current_version - md.max_versions
    if oldest > 0:
        print(f"(v1..v{oldest} pruned by KV v2 history retention)")
    return 0


def request_via_controller(secret_id: str, actor: str, reason: str) -> dict:
    """POST /request on the controller's loopback, through `oc exec`.

    The Ansible token may only read KV metadata, and a root-namespace token
    cannot hold the namespace's operator policy; so the operator's authority
    here is Kubernetes RBAC (pods/exec in sg-rotation), and the controller
    records the request in Vault with that provenance in the actor.
    """
    import subprocess
    body = json.dumps({"secret": secret_id, "actor": actor, "reason": reason})
    code = ("import sys,urllib.request,urllib.error;"
            "r=urllib.request.Request('http://127.0.0.1:8080/request',data=sys.stdin.read().encode(),"
            "headers={'Content-Type':'application/json'},method='POST')\n"
            "try:\n print(urllib.request.urlopen(r,timeout=10).read().decode())\n"
            "except urllib.error.HTTPError as e:\n print(e.read().decode()); sys.exit(1)")
    env = dict(os.environ, KUBECONFIG=str(ROOT / ".secrets/kube/config"))
    proc = subprocess.run(["oc", "-n", "sg-rotation", "exec", "-i", "deploy/rotation-controller", "-c", "controller",
                           "--", "python3", "-c", code], input=body, capture_output=True, text=True, env=env, timeout=30)
    if proc.returncode != 0:
        raise RuntimeError((proc.stdout or proc.stderr).strip() or "controller unreachable — is the add-on installed?")
    return json.loads(proc.stdout)


def cmd_rotate(args) -> int:
    cfg, vault = config(), vault_client()
    secret = cfg.secret(args.secret)
    md = vault.read_metadata(secret.rel_path)
    before = md.current_version if md else 0
    actor = f"cli:{getpass.getuser()} via kubernetes exec"
    try:
        result = request_via_controller(secret.id, actor, args.reason)
    except (RuntimeError, ValueError, OSError) as exc:
        print(f"request refused: {exc}", file=sys.stderr)
        return 1
    print(f"requested rotation of {secret.id} (request {result['request_id'][:8]}, actor {actor}); waiting...")
    deadline = time.time() + args.wait
    while time.time() < deadline:
        time.sleep(2)
        md = vault.read_metadata(secret.rel_path)
        if md and md.current_version > before:
            records = h.decode(md.custom)
            rec, old = records.get(md.current_version), records.get(before)
            if rec is None:
                continue        # written; record follows in the same loop
            print(f"rotated: v{before} -> v{md.current_version}  "
                  f"({old.fingerprint if old else '?'} -> {rec.fingerprint}, trigger {rec.trigger})")
            return 0
    print(f"no new version within {args.wait}s — is the controller running? (make rotation-status)", file=sys.stderr)
    return 1


def cmd_read(args) -> int:
    cfg, vault = config(), vault_client()
    secret = cfg.secret(args.secret)
    value = vault.read_value(secret.rel_path)
    if value is None:
        print(f"{secret.id}: not onboarded yet")
        return 1
    print(f"read {secret.id}: fingerprint {fingerprint(value)} (value not shown)")
    return 0


def cmd_report(args) -> int:
    cfg, vault = config(), vault_client()
    results = [compliance.evaluate(s, cfg, vault.read_metadata(s.rel_path), now()) for s in cfg.secrets]
    controller = os.environ.get("ROTATION_CONTROLLER_STATE", "unknown")
    report = {"summary": compliance.summary(results, now(), controller), "secrets": results}
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD / "compliance.json").write_text(json.dumps(report, indent=2) + "\n")
    s = report["summary"]
    lines = [f"# KV rotation compliance — {s['generated_at']}", "",
             f"Controller: {controller}. Compliant: {s['compliant']}/{s['total']} ({s['compliance_percent']}%).", "",
             "| Secret | Type | Version | Age | Compliant | Reasons |", "| --- | --- | --- | --- | --- | --- |"]
    rows = []
    for r in results:
        age = f"{r['age_seconds']}s / {r['max_age_seconds']}s" if r.get("age_seconds") is not None else "-"
        lines.append(f"| {r['secret']} | {r['type']} | v{r.get('version', '-')} | {age} | "
                     f"{'yes' if r['compliant'] else 'no'} | {'; '.join(r['reasons']) or '-'} |")
        rows.append([r["secret"], r["type"], f"v{r.get('version', '-')}", age,
                     "yes" if r["compliant"] else "NO", "; ".join(r["reasons"]) or "-"])
    (BUILD / "compliance.md").write_text("\n".join(lines) + "\n")
    print(f"controller: {controller}   compliant: {s['compliant']}/{s['total']} ({s['compliance_percent']}%)")
    print(table(rows, ["SECRET", "TYPE", "VERSION", "AGE / MAX", "COMPLIANT", "REASONS"]))
    print(f"report: {BUILD.relative_to(ROOT)}/compliance.json, compliance.md")
    return 0 if s["non_compliant"] == 0 else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="rotation", description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("status")
    p = sub.add_parser("history"); p.add_argument("secret"); p.add_argument("--reveal", action="store_true")  # noqa: E702
    p = sub.add_parser("rotate"); p.add_argument("secret"); p.add_argument("--reason", default="manual request")  # noqa: E702
    p.add_argument("--wait", type=int, default=45)
    p = sub.add_parser("read"); p.add_argument("secret")  # noqa: E702
    sub.add_parser("report")
    args = parser.parse_args(argv)
    try:
        return {"status": cmd_status, "history": cmd_history, "rotate": cmd_rotate,
                "read": cmd_read, "report": cmd_report}[args.cmd](args)
    except ConfigError as exc:
        print(f"config: {exc}", file=sys.stderr)
        return 2
    except FileNotFoundError as exc:
        print(f"missing {exc.filename} — is the lab converged? (make lab)", file=sys.stderr)
        return 2
    except (VaultError, Unreachable) as exc:
        print(f"vault: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
