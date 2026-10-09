# Prompt 01 — OpenShift Local cluster, the substrate contract, repo spine

---

## System Prompt Header

### 1. Persona & Role

You are a **Principal Platform & DevSecOps Engineer** specialising in
HashiCorp Enterprise architecture (Vault, Terraform), Red Hat OpenShift /
Kubernetes, and Ansible automation. Your output must exhibit:

- **Strict separation of concerns** — Terraform builds the house (anything
  with an API and a lifecycle: Kubernetes objects, Helm releases, Vault
  structure), Ansible decorates it (anything with an order and a moment:
  init, unseal, credentials, people, seeds, proof), the Vault Secrets
  Operator delivers secrets to workloads. Vault policy enforces the line.
- **Defensive, idempotent automation** — every script, playbook, and HCL
  block is re-runnable: a second `make lab` reports every plan empty and
  every Ansible phase `changed=0`.
- **Security by default** — zero hard-coded credentials, no secret value in
  Terraform state, short-lived tokens, mandatory CA verification (never
  `-tls-skip-verify`), least-privilege RBAC, NetworkPolicies and Vault
  policies.
- **Substrate agnosticism** — strict adherence to the `cluster` output
  contract; no substrate details (`crc`, `vfkit`, `api.crc.testing`,
  `apps-crc.testing`) outside `terraform/infra/` and `scripts/crc-*.sh`.

### 2. Target Audience

Tailor all deliverables, code comments, log output, and generated
documentation for three audiences:

| Audience | Focus | What they need |
| --- | --- | --- |
| **Enterprise Architects & Platform Engineers** | Layer separation, the tool boundary, substrate independence | See clearly *why* the design moves from CRC to bare-metal OCP or ROSA without changing a playbook, a policy or a VSO resource |
| **Operators running `make lab`** | Reproducibility, zero manual intervention, deterministic failures | Pre-flight validations, readable progress, explicit failure reasons (missing pull secret, VSO CSV not ready, stale Terraform outputs), the exact phase to resume |
| **AppDev & Security Teams** | Secret consumption without token exposure | Examples built on VSO resources and the Vault Agent sidecar, never direct API calls from application pods |

### 3. Operational Invariants (always enforced)

1. **Substrate isolation** — only `terraform/infra/` and `scripts/crc-*.sh`
   may reference the substrate. Everything else consumes the `cluster`
   contract (a grep in `make check` proves it).
2. **CSV gate** — never plan or apply a VSO resource until the Vault Secrets
   Operator CSV reports `phase=Succeeded`.
3. **Explicit namespaces** — set the Vault namespace explicitly on every
   task and resource; `tf-run.sh` unsets `VAULT_NAMESPACE`.
4. **Token hygiene** — each tool uses only its own bootstrap token on each
   Vault (`sg-tf-seal`, `sg-ansible-seal`, `sg-tf-platform`,
   `sg-ansible-platform`); root is break-glass only. **No seal token
   exists**: the cluster unseals through the seal agent. Agent tokens come
   from auto-auth and are checked for `renewable` and remaining TTL.
5. **No secret value in Terraform state** — licence, keys, init output,
   tokens, secret-ids and passwords are written by Ansible (`no_log`);
   Terraform references Secrets by name only.
6. **No blind copies** — consult `red_doors`, `golden_ticket` and
   `red_pass` for proven patterns, then adapt them to the Shift Gear
   contract. `00_01_shift_gear.md` wins on any conflict.

### 4. Execution Deliverables Standard

For every prompt executed under this specification:

- Provide production-ready, fully written files — no placeholders,
  no `TODO` comments, no truncated snippets.
- Append a clear **Execution Log** recording:
  1. What was created or configured.
  2. Deviations from predecessor projects and the architectural rationale.
  3. Validation steps executed to confirm convergence and zero-diff state.

---

## Context

Read `00_01_shift_gear.md` first, especially **§2 (the substrate contract)**,
**§4 (phases, ownership, the tool boundary)** and **§5 (lessons)**.

The Mac is Apple Silicon (arm64). OpenShift Local is installed
(`/usr/local/bin/crc`, CRC 2.64, OpenShift 4.22.14, bundle already in
`~/.crc/cache`). **A CRC VM from a previous project (Red Doors) may exist in
a stopped state.** Shift Gear builds from scratch: the old VM is destroyed
deliberately with `make crc-delete` before the first `make crc-up`. The
Podman machine is normally stopped while Shift Gear runs — the two VMs must
not compete for memory (past incidents: CPU starvation → VM clock drift →
JWT/TOTP failures).

This prompt implements the **substrate layer** and the **foundation**.
CRC's lifecycle lives in `scripts/crc-*.sh`; `terraform/infra/` reads the
running cluster and emits the contract; `terraform/foundation/` starts with
the namespaces and grows in later prompts. Nothing above `infra` mentions
CRC.

### Starting state (observed)

```text
❯ crc status
CRC VM:          Stopped
OpenShift:       Stopped (v4.22.14)
Disk Usage:      0B of 0B (Inside the CRC VM)
Cache Usage:     39.45 GB
Cache Directory: /Users/raymon.epping/.crc/cache
```

**Do not `crc start` this VM.** The entry point is `make crc-delete` (or
`make crc-reset`).

`shift_gear/` already has: README, CHANGELOG, CONTRIBUTING, LICENSE (GPLv3),
`.gitignore`, `.dockerignore`, `.gitleaks.toml`, `.env.example`, `.github/`
(gitleaks + release workflows), `docs/`.

Canonical references: `../red_doors/prompts/base_project/01_01_openshift_local_cluster.md`
and its execution log (apply every deviation found there);
`../golden_ticket/scripts/` (`common.sh`, `tf-run.sh`, `ansible-run.sh`,
`ansible-env.sh`, `phases.txt`, `lab.sh`) and
`../golden_ticket/ansible/plugins/callback/gt_stats.py`.

## Goal

A running, correctly sized OpenShift Local cluster that `make` can create,
start, stop, inspect and destroy, the `cluster` contract emitted from it,
the namespaces, and the repository spine every later prompt builds on.
**The goal is not "CRC running". The goal is "the cluster contract is
satisfied by a running CRC".**

## Deliverables

### CRC lifecycle (`scripts/crc-*.sh`, the only scripts that know CRC)

#### `make crc-delete` (idempotent destructive reset)

Run deliberately once before the first `make crc-up`, never automatically.

```bash
#!/usr/bin/env bash
# scripts/crc-delete.sh — destroy the CRC VM; keep the bundle cache and the pull secret.
set -euo pipefail
status=$(crc status --output json 2>/dev/null | jq -r '.crcStatus // empty' 2>/dev/null || true)
if [[ -z ${status} || ${status} == "No CRC instance"* ]]; then
  echo "==> No CRC instance found; nothing to delete."
  exit 0
fi
crc stop 2>/dev/null || true
crc delete --force
echo "==> CRC VM deleted. Run 'make crc-up' to create a fresh instance."
```

Verify the JSON field names against the installed `crc status --output
json` before relying on them, and record the real output in the log.
Never deletes `~/.crc/cache` or `.secrets/crc/pull-secret.json`. Afterwards
`crc status` shows that no VM exists.

#### `make crc-up` (create or start; idempotent on a running VM)

- `crc config set preset openshift`, `cpus 8`, `memory 24576`,
  `disk-size 80`, `consent-telemetry no`. Justify the numbers in a comment
  (OpenShift ≈ 10–11 GB; Vault ×4 + seal agent, Keycloak, OpenLDAP,
  Postgres, workloads, VSO, API, UI ≈ 7 GB; headroom for builds). CRC does
  not persist a value equal to its default — treat "Default value 'X' is
  used" as X in the idempotency check (Red Doors 01).
- Pull secret from `.secrets/crc/pull-secret.json` (gitignored); fail with
  a clear message if missing (lesson 17).
- Running → `==> CRC already running`. Stopped → `crc start`. No VM →
  `crc setup` then `crc start`.
- After start: copy the system:admin kubeconfig
  (`~/.crc/machines/crc/kubeconfig`) to `.secrets/kube/config` (`0600`).
  Every script and provider uses that file — never `~/.kube/config`.
  (The kubeadmin token expires in 24 h; the system:admin client
  certificate does not.) Also export the router CA to
  `.secrets/kube/ingress-ca.pem`
  (`openshift-config-managed/default-ingress-cert`).
- Run `scripts/crc-post-start.sh` after every start (chrony step +
  persistent hardening; see prompt 07).
- Refuse to start while the Podman machine runs, unless `ALLOW_PODMAN=1`.

`make crc-reset` = `make crc-delete && make crc-up` (*"Destroy the existing
CRC VM and build a fresh one from scratch."*). Also `crc-down` (stop, keep
VM), `crc-status`, `crc-console` (web console + kubeadmin credentials).

### `terraform/infra/` — the contract root

The only Terraform root that knows the substrate. No resources that change
the cluster: it reads and emits.

- `variables.tf` — `kubeconfig_path` and `api_url` (the only substrate
  inputs), with validations.
- `main.tf` — `kubernetes` provider on the kubeconfig;
  `data "kubernetes_resource"` for `ingresses.config.openshift.io/cluster`
  (→ `apps_domain` from `spec.domain`) and
  `networks.config.openshift.io/cluster` (→ `pod_cidr` from
  `status.clusterNetwork[0].cidr`). Verify the field paths on the running
  cluster and record them.
- `outputs.tf` — the `cluster` object exactly as in `00_01 §2`, every value
  from a variable or a data source.
- `tests/contract.tftest.hcl` — mock provider; asserts every field of
  `cluster` is present and non-empty and that `apps_domain` has no scheme.

### `terraform/foundation/` — namespaces now, more later

`kubernetes_namespace` for `sg-vault-seal`, `sg-vault`, `sg-identity`,
`sg-workloads`, `sg-app`, each labelled
`app.kubernetes.io/part-of=shift-gear`. Reads the contract through
`terraform_remote_state` (local backend path under `.secrets/terraform/`).
Later prompts add RBAC, NetworkPolicies, Routes, the VSO Subscription and
build objects here. `tests/` with at least one mock-provider test (namespace
names match `^sg-[a-z0-9-]+$`).

### Wrappers (ported from golden_ticket)

- `scripts/common.sh` — paths, `info`/`die`, `require_cmd`, bash ≥ 4 guard
  (`#!/usr/bin/env bash`; macOS `/bin/bash` is 3.2).
- `scripts/tf-run.sh <root> <init|plan|apply|drift|test>` — unsets
  `VAULT_NAMESPACE`; exports `KUBE_CONFIG_PATH` from the contract; exports
  `VAULT_TOKEN` **only** for `seal` (`.secrets/tokens/tf-seal`) and
  `platform` (`.secrets/tokens/tf-platform`) and `VAULT_ADDR`/`VAULT_CACERT`
  for those roots; state under `.secrets/terraform/<root>/`; `chmod 600` on
  state after every command; after apply writes the root's outputs to
  `.build/terraform/<root>.json` (non-secret; outputs marked sensitive are
  never written); `drift` exits 2 on changes.
- `scripts/ansible-env.sh` — allow-listed `.env` parser without `source` or
  `eval`: `ALLOWED_KEYS=(VAULT_LICENSE)`; existing environment wins; never
  echoes values. (`RHSM_*` keys in `.env` are ignored on purpose — §3.)
- `scripts/ansible-run.sh <phase>` — sources `ansible-env.sh`, sets
  `SG_PHASE` for the callback, runs `ansible/<phase>.yml`.

### Ansible scaffold

- `ansible.cfg`: inventory `ansible/inventory/localhost.yml`
  (`localhost ansible_connection=local`), roles path, `callback_plugins =
  ./ansible/plugins/callback`, `callbacks_enabled = sg_stats,
  ansible.posix.profile_tasks`, interpreter set explicitly. No SSH settings —
  there is no SSH in Shift Gear.
- `ansible/group_vars/all/terraform.yml` — loads
  `.build/terraform/<root>.json` for every root that exists (lesson 14).
- `ansible/requirements.yml` — pinned: `kubernetes.core`,
  `community.general`, `community.crypto`, `ansible.posix`. Installed into
  `.cache/ansible/collections` by `scripts/ansible-deps.sh` (force-install
  when a pinned version is missing; golden_ticket D5).
- `ansible/plugins/callback/sg_stats.py` — port of `gt_stats`: writes
  `.build/ansible-stats/<phase>.json` with counts only
  (`{"changed_total": 0, "hosts": {"localhost": {"changed": 0, "ok": 12}}}`),
  plus `tests/test_sg_stats.py`.
- Playbook stubs, one per Ansible phase in `phases.txt` (`prepare`,
  `seal-init`, `agent`, `bootstrap`, `identity`, `configure`, `ux`,
  `validate`), plus `preamble.yml` (imported by every phase) and
  `unseal.yml`. Each stub states its purpose and which prompt fills it in.

### `scripts/phases.txt` — the only phase list

Write the full list from `00_01 §4` now (format `<tool> <name>`, comments
allowed). `scripts/lab.sh` runs the phases in order and stops at the first
phase whose root or playbook does not exist yet, printing
`==> lab: stopped before <phase> (not implemented yet)`; so `make lab` is
useful from this prompt on. On failure it prints the exact resume command.

### Repo layout

```text
deploy/       Helm values + manifests rendered by Terraform (vault-seal/, vault/, seal-agent/, identity/, workloads/, app/)
terraform/    infra/ (contract) · foundation/ · workloads/ · seal/ · platform/ — each with tests/
ansible/      playbooks per phase, roles/, group_vars/, plugins/callback/
policies/     bootstrap/ (the four tool policies) + seal/ + platform/ (.hcl, ≤ 15 lines each)
scripts/      bash helpers (set -euo pipefail, shellcheck-clean, bash ≥ 4 guard)
api/          Express API (frontend prompt 01_01)
ui/           Nuxt 4 UI (frontend prompts; starts from ../golden_ticket/ux/)
.secrets/     everything secret (gitignored, 0700 dir / 0600 files): crc/, kube/, tls/, tokens/, terraform/, *-init.json
.build/       non-secret evidence (gitignored): terraform/, ansible-stats/, gates/, *.json
.cache/       collections, downloads (gitignored)
docs/         documentation
```

- `.gitignore` covers `.secrets/`, `.build/`, `.cache/`, `.env`,
  `*.kubeconfig`, `*.tfstate*`, `.terraform/`, `node_modules`, `.nuxt`,
  `.output`, `._*`. Verify with `git check-ignore`.
- `.dockerignore` adds `._*`, `.secrets`, `.build`, `node_modules`.
- `.gitleaks.toml`: keep the defaults; extend the allow-list only for
  generated test fixtures, each with a comment.

### Makefile (self-documenting `make help`)

`crc-delete`, `crc-reset`, `crc-up`, `crc-down`, `crc-status`,
`crc-console`, `deps`, `infra`, `foundation`, `lab`, `status`, `help`, plus
stubs (`@echo "not yet implemented (prompt NN)"`) for every later target:
`prepare`, `workloads`, `seal-init`, `seal`, `agent`, `bootstrap`,
`platform`, `identity`, `configure`, `ux`, `validate`, `unseal`, `check`,
`idempotency`, `drift`, `secret-scan`, `boundary`, `rotation-proof`, `up`,
`down`, `verify`, `reset`. Phase targets call `tf-run.sh` / `ansible-run.sh`;
none duplicates logic `lab.sh` owns.

## Validation

```sh
make crc-delete && make crc-delete   # second run: "nothing to delete"
make crc-up && make crc-up           # second run: "CRC already running"
make status                          # 1 node Ready; no Degraded cluster operators
make infra && make foundation        # applies
terraform -chdir=terraform/infra output -json cluster   # every field non-empty, apps_domain discovered
./scripts/tf-run.sh infra drift && ./scripts/tf-run.sh foundation drift   # exit 0
oc --kubeconfig .secrets/kube/config get ns -l app.kubernetes.io/part-of=shift-gear   # 5
make lab                             # runs infra + foundation, stops before prepare with the message
grep -rnE 'crc|vfkit|apps-crc' terraform/foundation ansible scripts --exclude='crc-*.sh'   # zero matches
shellcheck -x scripts/*.sh && python3 -m unittest discover -s tests   # clean
git status --short                   # nothing secret staged
```

Also record: time to first start, VM memory at idle, whether a start after
a Mac sleep needs `crc-post-start.sh` to correct the clock.

## Out of scope

Vault, identity, apps, operators.

## Execution log

Appended by each run: what was done, deviations and why, validation output.
