# Prompt 06 — Ansible: configuration complete, preamble, validation

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

Prompts 01–05 are done: `make lab` is green through the first part of
`configure`; VSO syncs both demo secrets.

Canonical references:

- `../golden_ticket/ansible/` — `preamble.yml`, `validate.yml`,
  `roles/lab_common`, `roles/vault_identity` (compare-before-write idioms),
  `scripts/automation-digest.sh`, `scripts/idempotency-allow.txt`,
  `docs/decisions.md` D12–D14. **Primary source** for structure and style.
- `../red_pass/ansible/` — role idioms (policy and mount drift handling,
  check-mode honesty).
- `../red_doors/` — Vault API details on OpenShift (cert auth error
  classification, Sentinel EGP).

Apply lessons 13–31, specifically:

- **Lesson 20:** Ansible uses `sg-ansible-platform` on the cluster and
  `sg-ansible-seal` on the seal Vault — never root, never a Terraform token.
  If a task needs `sys/mounts` or `sys/policies` writes, it belongs in
  `terraform/platform`, not here.
- **Lesson 19:** no `crc`, `vfkit` or `apps-crc` anywhere in `ansible/`;
  every URL is derived from the contract (`cluster.apps_domain`, …).
- **Lesson 16:** the Vault namespace set explicitly on every task.
- **Lesson 26:** idempotency is a real re-run; check mode is for drift.

### Task hygiene

Every `command:` uses `argv:`, explicit `changed_when:` and
`failed_when:`; no `shell:` with interpolation. Prefer `ansible.builtin.uri`
for Vault and `kubernetes.core` for OpenShift. Every task that could print a
credential is `no_log`; secrets go only in headers and bodies, never in URLs
(lesson 30). Role-prefixed variable names (ansible-lint
`var-naming[no-role-prefix]`).

## Goal

The `configure` phase complete, every phase guarded by the same preamble,
and `validate.yml` proving the whole system from the outside. A second
`make lab` changes nothing.

## Deliverables

### `ansible/preamble.yml` (imported first by every phase)

- Assert the Terraform outputs the phase needs exist in
  `.build/terraform/<root>.json` **and** are newer than that root's state
  (lesson 14); otherwise fail with the `make <root>` to run.
- Assert the token file for this phase's Vault exists, then `lookup-self`:
  policies must be exactly the expected bootstrap policy (`sg-ansible-seal`
  or `sg-ansible-platform`); refuse root or any Terraform token with a clear
  message (an exported `VAULT_TOKEN` in the shell is ignored — the playbooks
  read the file).
- Vault reachable at the derived address with the project CA; namespace
  `shift-gear` exists (after `platform`).

### `ansible configure` — part 2 (`sg-ansible-platform`)

| Mount | Type | Roles |
| --- | --- | --- |
| `approle/` | AppRole | `sg-automation` (`token_ttl=15m`, `secret_id_num_uses=1`, lockout 3 / 30 s — lesson 3, `secret_id_bound_cidrs` and `token_bound_cidrs` = `cluster.pod_cidr` in canonical form) |
| `cert/` | TLS cert auth | `internal-client` (trusts the `pki-int` chain, `token_ttl=2m`). Vault answers **HTTP 500** (not 4xx) for an expired client cert at `auth/cert/login`: classify by the error text (`x509: certificate has expired`), map to `outcome: denied` |
| `kubernetes/` | (exists from prompt 05) | add `sg-api` (SA `sg-api`, ns `sg-app`, policy `sg-api`) and `sg-agent-demo` (SA `sg-agent-demo`, ns `sg-app`, policy `sg-agent-demo`) |

- **Agent demo**: Terraform `workloads` deploys `agent-demo` in `sg-app`
  (SA `sg-agent-demo`) with a Vault Agent sidecar (Kubernetes auth role
  `sg-agent-demo`, template renders `kv/shift-gear/agent/demo-secret` to
  `/vault/secrets/demo-secret`). Ansible seeds that KV path (generated,
  written only when absent) and checks the agent's token through the
  sidecar's own token sink metadata: `renewable=true`, TTL > 0 (lesson 15).
  The API reads the rendered file's key names (`/api/v1/agent/demo`).
- Mount drift: if a mount Ansible configures has a different type than
  Terraform declared, fail with both types — never retype. Auth role and
  policy writes compare before writing (normalise whitespace / list order;
  never round-trip `token_policies` — lesson 4).

### Platform policies (single definition; files in `policies/platform/`, applied by `terraform/platform`)

| Policy | Grants (namespace `shift-gear`) |
| --- | --- |
| `sg-engineer` | `read` `kv/data/shift-gear/config/*`; `update` `transit/encrypt/app-data`, `transit/decrypt/app-data`; `read` `database/creds/demo-reader`; `update` `pki-int/issue/internal-client` |
| `sg-operator` | `sg-engineer` + `update` `sys/leases/renew`, `sys/leases/revoke`; `update` `transit/keys/app-data/rotate` |
| `sg-approver` | `update` `sys/control-group/authorize`, `sys/control-group/request` |
| `sg-auditor` | `read` `sys/health`; `read`, `list` `identity/entity/id/*`, `identity/group/id/*`; `read` `sys/internal/counters/*` |
| `sg-vso` | `read` `kv/data/shift-gear/config/*`; `read` `database/creds/demo-reader` |
| `sg-api` | `update` `auth/approle/role/sg-automation/secret-id` (response wrapping enforced, `max_wrapping_ttl=2m`); `read` `sys/ha-status`, `sys/health`, `sys/policies/acl/*`; `read` `identity/entity/id/*`, `identity/group/id/*` |
| `sg-agent-demo` | `read` `kv/data/shift-gear/agent/*` |

Verify every path against the 2.1.0 API on the running cluster before
committing (e.g. key rotation is `transit/keys/<name>/rotate`; reading
`sys/audit` needs `sudo`, which is why `sg-auditor` reads audit through the
API instead).

### `ansible/validate.yml` (`make validate`, read-only)

Port golden_ticket's structure: every row is `pass|fail` with a reason,
written to `.build/validation.json` and `.build/gates/validation.json`
**before** the play decides pass or fail. Sections:

- **Pods**: every Vault pod Running, TLS valid against the project CA,
  `initialized`, unsealed, seal type `transit` (cluster) / `shamir` (seal
  Vault); licence valid with > 30 days.
- **Cluster**: exactly one active node, three Raft voters, version as
  declared in `group_vars`.
- **Seal chain**: no Vault pod has `VAULT_TOKEN` in its environment or a
  token in any mounted Secret; the seal agent holds a token (metrics or
  `lookup-self` through the agent from an allowed pod); exactly one valid
  secret-id for `seal-autounseal`; the rotator's last successful Job < 7 h
  ago; the agent's secret-id younger than 7 h.
- **Platform** (against `terraform/platform` outputs): the namespace, every
  mount, every policy, every token role exist.
- **Boundary**: a subset of `make boundary` (Terraform cannot mint a
  secret-id; Ansible cannot write a policy).
- **Identity**: the rows from `.build/identity-verify.json`, re-checked.
- **VSO**: both secrets synced within 2 × `refreshAfter`; no `VAULT_*` in
  workload pods.
- **Network**: from a short-lived probe pod in `sg-workloads`, the seal
  agent, the seal Vault, OpenLDAP and Keycloak's service port are refused.
- **Routes**: every Route answers through the router with the expected TLS
  mode; Vault UI 200; Keycloak discovery 200.

No token, raw Vault response or secret value in the files (the secret scan
proves it).

### `scripts/automation-digest.sh` and the convergence stamp

SHA-256 over sorted relative paths + contents of `ansible/**/*.{yml,yaml,j2}`,
`ansible.cfg`, `policies/**/*.hcl`, `terraform/**/*.tf`, `deploy/**`,
`scripts/phases.txt`. `scripts/lab.sh` writes `.build/convergence.json`
(`result`, `finished_at`, `automation_digest`) **only after all phases and
gates pass**; a failed run never updates it. The console compares the stamp
with the current digest (converged / outdated / never run). There is no
`converge.yml`: `phases.txt` is the order.

### `scripts/idempotency-allow.txt`

```text
# Format: <phase>  <reason>. Every line is a documented, deliberate change on a re-run.
ux  evidence ConfigMap sync: .build/*.json is regenerated on every run
```

Nothing else unless proven necessary and explained. (Keycloak user
federation is **not** an exception: it is skipped in check mode and reports
`ok` on a real re-run — golden_ticket D14.)

### `make check` additions

`ansible-playbook --syntax-check` on every playbook; `ansible-lint
--profile production`.

## Validation

```sh
make lab && make lab                 # second run: every plan empty, every Ansible phase changed=0
make validate                        # every row pass
jq '[.rows[] | select(.result!="pass")] | length' .build/validation.json   # 0
make check                           # all PASS, ansible-lint production clean
grep -rnE 'crc|vfkit|apps-crc' ansible/   # zero matches
```

## Out of scope

The console and the API (frontend prompts; the socket audit device is
enabled in the `ux` phase once the API collector runs). The gates and
scenarios (prompt 07).

## Execution log

Appended by each run: what was done, deviations and why, validation output.
