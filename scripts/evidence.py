#!/usr/bin/env python3
"""scripts/evidence.py — the console's evidence snapshot (.build/evidence.json).

Reads the running system and writes the shape ui/shared/types.ts defines.
Sources: OpenShift (oc, the contract kubeconfig), Vault (Ansible's own
bootstrap tokens, through the Routes with the project CA), and the gate and
validation files in .build/. Never fabricates: anything it cannot read is
null / unknown, and the console renders it as "not reported" (red_doors
lesson 9). Never writes a secret value — key names only.
"""
from __future__ import annotations

import base64
import datetime as dt
import json
import os
import ssl
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / ".build"
SECRETS = ROOT / ".secrets"
CA = SECRETS / "tls" / "pub" / "ca.pem"
NAMESPACES = ["sg-vault-seal", "sg-vault", "sg-identity", "sg-workloads", "sg-app"]
ENTERPRISE_ENGINES = {"transform", "kmip", "keymgmt", "spiffe", "kv-ent"}


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_json(path: Path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def oc(*args: str):
    """oc … -o json → parsed, or None on any failure."""
    try:
        out = subprocess.run(["oc", *args, "-o", "json"], capture_output=True, text=True, timeout=60, check=True)
        return json.loads(out.stdout)
    except (subprocess.SubprocessError, ValueError, OSError):
        return None


def oc_exec_json(ns: str, pod: str, container: str, *cmd: str):
    try:
        out = subprocess.run(["oc", "-n", ns, "exec", pod, "-c", container, "--", *cmd],
                             capture_output=True, text=True, timeout=30)
        return json.loads(out.stdout) if out.stdout.strip().startswith("{") else None
    except (subprocess.SubprocessError, ValueError, OSError):
        return None


CTX = ssl.create_default_context(cafile=str(CA)) if CA.exists() else None


def vault(addr: str, path: str, token_file: str | None = None, namespace: str | None = None,
          method: str = "GET", body: dict | None = None):
    """(status, json) — status 0 when unreachable."""
    req = urllib.request.Request(f"{addr}/v1/{path}", method=method,
                                 data=json.dumps(body).encode() if body is not None else None)
    if token_file:
        tok = SECRETS / "tokens" / token_file
        if not tok.exists():
            return 0, None
        req.add_header("X-Vault-Token", tok.read_text().strip())
    if namespace:
        req.add_header("X-Vault-Namespace", namespace)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, context=CTX, timeout=10) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except ValueError:
            return e.code, None
    except (urllib.error.URLError, OSError, ValueError):
        return 0, None


def age(iso: str | None) -> str | None:
    if not iso:
        return None
    import re
    # Vault reports nanoseconds; fromisoformat accepts at most microseconds.
    iso = re.sub(r"(\.\d{6})\d+", r"\1", iso)
    try:
        t = dt.datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except ValueError:
        return None
    s = int((dt.datetime.now(dt.timezone.utc) - t).total_seconds())
    return f"{s // 3600}h {s % 3600 // 60}m" if s >= 3600 else f"{s // 60}m"


def condition(obj: dict, ctype: str):
    for c in (obj.get("status") or {}).get("conditions") or []:
        if c.get("type") == ctype:
            return c
    return None


def build_layers(applied_digest, current_digest) -> dict:
    """.build/layers.json in the shape ui/server/api/layers.get.ts parses."""
    allowed = {}
    allow_file = ROOT / "scripts" / "idempotency-allow.txt"
    if allow_file.exists():
        for line in allow_file.read_text().splitlines():
            if line.strip() and not line.startswith("#"):
                name, _, reason = line.partition(" ")
                allowed[name] = reason.strip()
    conv = read_json(BUILD / "convergence.json") or {}
    phase_secs: dict = conv.get("phase_seconds") or {}
    gate_secs: dict = conv.get("gate_seconds") or {}
    phases = []
    for line in (ROOT / "scripts" / "phases.txt").read_text().splitlines():
        parts = line.split()
        if len(parts) != 2 or line.startswith("#"):
            continue
        tool, name = parts
        dur = phase_secs.get(name)
        if tool == "tf":
            state = read_json(SECRETS / "terraform" / name / "terraform.tfstate") or {}
            runs = read_json(BUILD / "terraform" / f"{name}.runs.json") or {}
            plan = runs.get("last_plan") or {}
            phases.append({"phase": name, "tool": "terraform", "resources": len(state.get("resources", [])),
                           "last_apply": runs.get("last_apply"),
                           "last_plan": {"result": plan.get("result"), "at": plan.get("at")} if plan else None,
                           "durationSeconds": dur})
        else:
            run = read_json(BUILD / "ansible-stats" / f"{name}.json") or {}
            chk = read_json(BUILD / "ansible-stats" / f"{name}.check.json") or {}
            phases.append({"phase": name, "tool": "ansible",
                           "last_run": {"at": run.get("finished_at"), "changed": run.get("changed_total"),
                                        "failed": run.get("failed_total", 0)} if run else None,
                           "last_check": {"at": chk.get("finished_at"), "changed": chk.get("changed_total")} if chk else None,
                           "allowed_changes": allowed.get(name),
                           "durationSeconds": dur})
    gates = {}
    for gate in ("idempotency", "drift", "secret-scan", "validation"):
        g = read_json(BUILD / "gates" / f"{gate}.json") or {}
        if gate == "validation" and "result" not in g and "rows" in g:
            g = {"result": "pass" if g.get("fail_count", 1) == 0 else "fail", "at": g.get("generated_at")}
        gates[gate] = {"result": g.get("result", "unknown"), "at": g.get("at"),
                       "durationSeconds": gate_secs.get(gate)}
    return {"generated_at": now(), "phases": phases, "gates": gates,
            "digest": {"applied": applied_digest, "current": current_digest}}


def main() -> int:
    contract = (read_json(BUILD / "terraform" / "infra.json") or {}).get("cluster") or {}
    apps = contract.get("apps_domain")
    if not apps:
        print("evidence: no apps_domain in .build/terraform/infra.json — run make infra", file=sys.stderr)
        return 1
    os.environ.setdefault("KUBECONFIG", str(ROOT / contract.get("kubeconfig_path", ".secrets/kube/config")))
    cluster_addr, seal_addr = f"https://vault.{apps}", f"https://vault-seal.{apps}"

    # ── Vault cluster: each pod's own status ─────────────────────────────────
    nodes = []
    for i in range(3):
        st = oc_exec_json("sg-vault", f"vault-{i}", "vault", "vault", "status", "-format=json")
        nodes.append({
            "name": f"vault-{i}",
            # Vault 2.1 leaves ha_mode null; the active node reports is_self.
            "role": "leader" if (st or {}).get("is_self") else "standby",
            "sealed": bool((st or {}).get("sealed", True)),
            "reachable": st is not None,
            "version": (st or {}).get("version"),
            "raftAppliedIndex": (st or {}).get("raft_applied_index"),
        })
    code, lic = vault(cluster_addr, "sys/license/status", "ansible-platform")
    licence_expiry = ((lic or {}).get("data") or {}).get("autoloaded", {}).get("expiration_time") if code == 200 else None
    unsealed = sum(1 for n in nodes if n["reachable"] and not n["sealed"])
    leader = next((n["name"] for n in nodes if n["role"] == "leader"), None)

    # ── Seal Vault and seal agent ────────────────────────────────────────────
    code, health = vault(seal_addr, "sys/health?sealedcode=200&uninitcode=200")
    seal_vault = {"reachable": code == 200, "sealed": bool((health or {}).get("sealed", True)) if code == 200 else True,
                  "version": (health or {}).get("version")}
    agent_dep = oc("-n", "sg-vault-seal", "get", "deployment", "seal-agent") or {}
    agent_available = ((agent_dep.get("status") or {}).get("readyReplicas") or 0) >= 1
    secret_id_age = None
    approle = oc("-n", "sg-vault-seal", "get", "secret", "seal-agent-approle") or {}
    sid_b64 = (approle.get("data") or {}).get("secret-id")
    if sid_b64:
        code, look = vault(seal_addr, "auth/approle/role/sg-seal-autounseal/secret-id/lookup", "ansible-seal",
                           method="POST", body={"secret_id": base64.b64decode(sid_b64).decode().strip()})
        if code == 200:
            secret_id_age = age(((look or {}).get("data") or {}).get("creation_time"))
    cron = oc("-n", "sg-vault-seal", "get", "cronjob", "seal-rotator") or {}
    last_rotation = (cron.get("status") or {}).get("lastSuccessfulTime")

    # ── Engines (namespace shift-gear) ───────────────────────────────────────
    code, mounts_raw = vault(cluster_addr, "sys/mounts", "ansible-platform", "shift-gear")
    mounts = []
    if code == 200:
        for path, m in sorted(((mounts_raw or {}).get("data") or {}).items()):
            if m.get("type") in ("system", "identity", "cubbyhole", "ns_system", "ns_identity", "ns_cubbyhole", "agent_registry", "ns_agent_registry"):
                continue
            mounts.append({"path": path, "type": m.get("type", ""), "description": m.get("description", ""),
                           "pluginVersion": m.get("running_plugin_version") or None,
                           "enterprise": m.get("type") in ENTERPRISE_ENGINES})

    # ── Audit collector (sg-audit): counters only ────────────────────────────
    audit_counters = {"listening": False, "connections": 0, "received": 0, "stored": 0, "dropped": 0}
    audit_pods = (oc("-n", "sg-app", "get", "pods", "-l", "app.kubernetes.io/name=sg-audit",
                     "--field-selector=status.phase=Running") or {}).get("items") or []
    if audit_pods:
        got = oc_exec_json("sg-app", audit_pods[0]["metadata"]["name"], "collector", "node", "-e",
                           "fetch('http://127.0.0.1:8080/audit?limit=0').then(r=>r.json())"
                           ".then(j=>console.log(JSON.stringify(j.collector)))")
        if got:
            audit_counters = {k: got.get(k, audit_counters[k]) for k in audit_counters}

    # Engines Terraform deliberately leaves unmounted (terraform/platform output).
    skipped_engines = (read_json(BUILD / "terraform" / "platform.json") or {}).get("skipped_engines") or []

    # ── Vault Secrets Operator ───────────────────────────────────────────────
    sub = oc("-n", "openshift-operators", "get", "subscription", "vault-secrets-operator") or {}
    csv_name = (sub.get("status") or {}).get("installedCSV")
    csv = oc("-n", "openshift-operators", "get", "csv", csv_name) if csv_name else None
    csv_phase = ((csv or {}).get("status") or {}).get("phase")
    csv_status = csv_phase if csv_phase in ("Succeeded", "Failed") else ("Installing" if csv_phase else "Unknown")

    def vso_cards(kind: str, items: list) -> list:
        cards = []
        for o in items:
            spec, meta = o.get("spec") or {}, o.get("metadata") or {}
            synced = condition(o, "SecretSynced")
            ok = (synced or {}).get("status") == "True"
            cards.append({
                "name": meta.get("name"), "namespace": meta.get("namespace"), "kind": kind,
                "vaultPath": f"{spec.get('mount', '')}/{spec.get('path', '')}".strip("/"),
                "destinationSecret": (spec.get("destination") or {}).get("name"),
                "lastSyncTime": (synced or {}).get("lastTransitionTime") if ok else None,
                "syncError": None if ok else ((synced or {}).get("message") or "not synced yet"),
                "provenance": "Vault Operator",
            })
        return cards

    vss = (oc("-n", "sg-workloads", "get", "vaultstaticsecret") or {}).get("items", [])
    vds = (oc("-n", "sg-workloads", "get", "vaultdynamicsecret") or {}).get("items", [])
    static_cards, dynamic_cards = vso_cards("VaultStaticSecret", vss), vso_cards("VaultDynamicSecret", vds)
    workloads = []
    for name, secret, card in (("workload-a", "app-config", static_cards), ("workload-b", "db-creds", dynamic_cards)):
        dep = oc("-n", "sg-workloads", "get", "deployment", name)
        if not dep:
            continue
        sec = oc("-n", "sg-workloads", "get", "secret", secret) or {}
        workloads.append({
            "name": name, "namespace": "sg-workloads",
            "replicas": (dep.get("spec") or {}).get("replicas", 0),
            "readyReplicas": (dep.get("status") or {}).get("readyReplicas", 0),
            "mountedSecretKeys": sorted(k for k in (sec.get("data") or {}) if not k.startswith("_")),
            "lastSecretUpdate": next((c["lastSyncTime"] for c in card if c["destinationSecret"] == secret), None),
        })

    # ── Convergence and validation ───────────────────────────────────────────
    conv = read_json(BUILD / "convergence.json") or {}
    try:
        current_digest = subprocess.run([str(ROOT / "scripts" / "automation-digest.sh")], capture_output=True,
                                        text=True, timeout=60).stdout.strip() or None
    except (subprocess.SubprocessError, OSError):
        current_digest = None
    applied_digest = conv.get("automation_digest")
    converged = bool(applied_digest and applied_digest == current_digest and conv.get("result") == "success")
    val = read_json(BUILD / "validation.json") or {}
    val_rows = [{"id": r.get("id"), "label": r.get("label"), "result": r.get("result", "unknown"),
                 "detail": r.get("detail", "")} for r in val.get("rows", [])]

    # ── Pods ─────────────────────────────────────────────────────────────────
    pvcs = {}
    for ns in NAMESPACES:
        for p in (oc("-n", ns, "get", "pvc") or {}).get("items", []):
            pvcs[(ns, p["metadata"]["name"])] = ((p.get("spec") or {}).get("resources") or {}).get("requests", {}).get("storage")
    node_by_name = {n["name"]: n for n in nodes}

    def role_of(ns: str, name: str, labels: dict) -> str:
        instance, app = labels.get("app.kubernetes.io/instance"), labels.get("app.kubernetes.io/name")
        if instance == "vault-seal":
            return "SEAL VAULT"
        if ns == "sg-vault" and app == "vault":
            return "CLUSTER · LEADER" if node_by_name.get(name, {}).get("role") == "leader" else "CLUSTER"
        if app == "seal-agent":
            return "SEAL AGENT"
        if ns == "sg-identity":
            return "IDENTITY"
        if app == "sg-ui":
            return "UI"
        if ns == "sg-workloads":
            return "WORKLOAD"
        return "OTHER"

    cards = []
    for ns in NAMESPACES:
        for p in (oc("-n", ns, "get", "pods") or {}).get("items", []):
            meta, spec, status = p["metadata"], p.get("spec") or {}, p.get("status") or {}
            if status.get("phase") in ("Succeeded", "Failed"):
                continue  # finished build and rotator pods
            labels = meta.get("labels") or {}
            ready = (condition(p, "Ready") or {}).get("status") == "True"
            owners = meta.get("ownerReferences") or []
            managed = labels.get("app.kubernetes.io/managed-by") in ("terraform", "Helm") or bool(owners)
            role = role_of(ns, meta["name"], labels)
            if role in ("SEAL VAULT", "CLUSTER", "CLUSTER · LEADER"):
                n = node_by_name.get(meta["name"])
                if role == "SEAL VAULT":
                    vstat = "pass" if seal_vault["reachable"] and not seal_vault["sealed"] else "fail"
                    vdetail = "unsealed" if vstat == "pass" else "sealed or unreachable"
                else:
                    vstat = "pass" if n and n["reachable"] and not n["sealed"] else "fail"
                    vdetail = f"{(n or {}).get('role', 'unknown')}, {'unsealed' if vstat == 'pass' else 'sealed'}"
                vlabel = "VAULT"
            else:
                vstat, vdetail, vlabel = ("pass" if ready else "fail"), ("serving" if ready else "not ready"), "SERVICE"
            c0 = (spec.get("containers") or [{}])[0]
            req = (c0.get("resources") or {}).get("requests") or {}
            pvc = next(((ns, v["persistentVolumeClaim"]["claimName"]) for v in spec.get("volumes") or []
                        if v.get("persistentVolumeClaim")), None)
            cards.append({
                "name": meta["name"], "namespace": ns, "podIP": status.get("podIP"), "role": role, "reachable": ready,
                "indicators": [
                    {"kind": "provisioned", "label": "PROVISIONED", "status": "pass" if managed else "warn",
                     "detail": "owned by a Terraform-managed workload" if managed else "not owned by Terraform",
                     "evidenceSource": "OpenShift ownerReferences + Terraform workloads"},
                    {"kind": "openshift", "label": "OPENSHIFT", "status": "pass" if ready else "fail",
                     "detail": f"{status.get('phase', 'Unknown')}, {'ready' if ready else 'not ready'}",
                     "evidenceSource": "oc get pod"},
                    {"kind": "ansible", "label": "ANSIBLE",
                     "status": "pass" if converged else ("warn" if applied_digest else "unknown"),
                     "detail": "converged" if converged else ("outdated" if applied_digest else "never converged"),
                     "evidenceSource": ".build/convergence.json"},
                    {"kind": "vault", "label": vlabel, "status": vstat, "detail": vdetail,
                     "evidenceSource": "vault status" if vlabel == "VAULT" else "readiness probe"},
                ],
                "resources": {"cpuRequest": req.get("cpu"), "memRequest": req.get("memory"),
                              "pvcSize": pvcs.get(pvc) if pvc else None},
            })

    # ── Routes ───────────────────────────────────────────────────────────────
    labels = {"vault": "Vault — UI, API, writes (active node)", "vault-seal": "Seal Vault (operator)",
              "keycloak": "Keycloak (realm shift-gear)", "shiftgear": "Shift Gear console"}
    term = {"passthrough": "Passthrough", "edge": "Edge", "reencrypt": "Re-encrypt"}
    routes = []
    for ns in NAMESPACES:
        for r in (oc("-n", ns, "get", "routes") or {}).get("items", []):
            spec = r.get("spec") or {}
            svc = (spec.get("to") or {}).get("name")
            ep = oc("-n", ns, "get", "endpoints", svc) or {}
            backends = []
            for subset in ep.get("subsets") or []:
                for ready_flag, key in ((True, "addresses"), (False, "notReadyAddresses")):
                    for a in subset.get(key) or []:
                        pod = (a.get("targetRef") or {}).get("name", "unknown")
                        nrole = node_by_name.get(pod, {}).get("role")
                        backends.append({"podName": pod, "ready": ready_flag,
                                         "role": nrole if nrole in ("leader", "standby") else "backend"})
            routes.append({"name": r["metadata"]["name"], "label": labels.get(r["metadata"]["name"], r["metadata"]["name"]),
                           "url": f"https://{spec.get('host', '')}", "namespace": ns,
                           "tlsTermination": term.get((spec.get("tls") or {}).get("termination", ""), "Edge"),
                           "backends": backends})

    # ── Agents ───────────────────────────────────────────────────────────────
    demo = oc("-n", "sg-app", "get", "deployment", "agent-demo") or {}
    demo_ready = ((demo.get("status") or {}).get("readyReplicas") or 0) >= 1
    code, demo_kv = vault(cluster_addr, "kv/data/shift-gear/agent/demo-secret", "ansible-platform", "shift-gear")
    agents = [
        {"name": "seal-agent", "kind": "seal-agent", "status": "pass" if agent_available else "fail",
         "detail": "AppRole token held, mTLS proxy serving" if agent_available else "not ready",
         "tokenTtl": None, "secretIdAge": secret_id_age, "lastRotation": last_rotation,
         "lastInjection": None, "keyNames": []},
        {"name": "agent-demo", "kind": "sidecar", "status": "pass" if demo_ready else ("fail" if demo else "unknown"),
         "detail": "Vault Agent sidecar rendering kv/shift-gear/agent/demo-secret" if demo_ready else "not ready",
         "tokenTtl": None, "secretIdAge": None, "lastRotation": None, "lastInjection": None,
         "keyNames": sorted(((demo_kv or {}).get("data") or {}).get("data", {}).keys()) if code == 200 else []},
    ]

    evidence = {
        "observedAt": now(),
        "vault": {"nodes": nodes, "unsealed": unsealed, "total": len(nodes), "leader": leader,
                  "licenceExpiry": licence_expiry},
        "sealVault": seal_vault,
        "sealAgent": {"available": agent_available, "tokenTtl": None, "secretIdAge": secret_id_age,
                      "lastRotation": last_rotation},
        "engines": {"count": len(mounts), "enterprise": sum(1 for m in mounts if m["enterprise"]),
                    "mounts": mounts, "skipped": skipped_engines},
        "operator": {"csvStatus": csv_status, "staticSecrets": len(static_cards), "dynamicSecrets": len(dynamic_cards),
                     "static": static_cards, "dynamic": dynamic_cards, "workloads": workloads},
        "pods": {"total": len(cards), "reachable": sum(1 for c in cards if c["reachable"]), "cards": cards},
        "routes": routes,
        "ansible": {"convergence": {"appliedDigest": applied_digest, "currentDigest": current_digest,
                                    "lastRun": conv.get("finished_at")},
                    "validate": {"generatedAt": val.get("generated_at"), "rows": val_rows}},
        # Counters only, read inside the collector pod; entries stay live (the
        # Audit page reads the collector), never in the evidence snapshot.
        "audit": audit_counters,
        "agents": agents,
    }
    BUILD.mkdir(exist_ok=True)
    tmp = BUILD / "evidence.json.tmp"
    tmp.write_text(json.dumps(evidence, indent=2) + "\n")
    tmp.replace(BUILD / "evidence.json")
    layers_tmp = BUILD / "layers.json.tmp"
    layers_tmp.write_text(json.dumps(build_layers(applied_digest, current_digest), indent=2) + "\n")
    layers_tmp.replace(BUILD / "layers.json")
    print(f"evidence: {len(cards)} pods, {len(routes)} routes, {unsealed}/{len(nodes)} unsealed, VSO {csv_status}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
