# Prompt 03 — Cluster structure (Terraform), the tool boundary, static gate

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

Prompt 02 is done: the cluster auto-unseals through the seal agent;
`.secrets/tokens/` holds the four bootstrap tokens; `make lab` is green
through `bootstrap`.

Canonical references:

- `../golden_ticket/terraform/platform/` (namespaces, mounts, `secret/`
  protection, licence-aware engines, token roles, `check` block, tests),
  `../golden_ticket/policies/bootstrap/gt-tf-platform.hcl` and
  `gt-ansible-platform.hcl`, `../golden_ticket/scripts/boundary-check.sh`,
  `scripts/check.sh`, `docs/decisions.md` D9–D11.
- `../red_doors/prompts/base_project/03_01_vault_terraform_baseline.md` and
  its execution log (Vault provider through the passthrough Route + CA,
  `VAULT_NAMESPACE` double-prefix).

## Goal

The structure inside the cluster, owned by Terraform with `sg-tf-platform`:
an Enterprise namespace, the secret engine mounts, the ACL policies, the
token roles and the file audit device. Plus the proofs that the tool
boundary holds and that the static gate is green. Second run: no changes.

## Deliverables

### `terraform/platform/` (Vault provider, `sg-tf-platform`)

Provider address `https://vault.<apps_domain>` (derived from the contract)
with `vault-tls`'s CA; `tf-run.sh` exports the token and unsets
`VAULT_NAMESPACE` (lesson 16). Everything below lives in Enterprise
namespace **`shift-gear`** unless stated.

- `vault_namespace.shift_gear`.
- Mounts: `kv` (KV v2), `transit` (key `app-data`, non-exportable,
  `deletion_allowed = false`), `pki` (root, internal key, 10 y) and
  `pki-int` (intermediate signed by `pki`, role `internal-client`:
  client certs, `ttl=1h`, `max_ttl=4h`), `database` (mount only — the
  connection holds a password, so Ansible configures it in prompt 05).
  Optional licence-aware engines as in golden_ticket (D9): read
  `sys/license/status`, unmark only the feature names.
- **`kv/` protection (lesson 22, D11):** `prevent_destroy` on
  `vault_mount.kv`, **and** `sg-tf-platform` has `create/read/update` but
  no `delete` on `shift-gear/sys/mounts/kv` and no `sys/remount`. Prove it:
  delete the resource block, apply, Vault answers 403, `kv/` survives,
  restore, plan clean. Record in the log and `docs/decisions.md`.
- ACL policies from `policies/platform/*.hcl` (≤ 15 lines each, plain-English
  header): `sg-engineer`, `sg-operator`, `sg-approver`, `sg-auditor`,
  `sg-vso`, `sg-api`, `sg-agent-demo` (grants as listed in prompt 06's
  table, which is the single definition).
- Token role `sg-ui` for the console (one policy `sg-api`, orphan,
  periodic, `token_bound_cidrs` = what Vault actually sees for API calls —
  lesson 31: verify from a request whether that is the pod IP range or the
  router).
- `vault_audit` file device to stdout (`file_path = "stdout"`). The socket
  device to the API collector is Ansible's (prompt 06): it needs the
  collector to be running at the moment it is enabled.
- `data "http"` health read outside a `check` block that only asserts
  (D10), so `plan -detailed-exitcode` stays 0.
- Outputs (non-secret): namespace, mounts, policies, token roles — the
  validation contract for `validate.yml`.
- `tests/`: mock providers; undeclared namespaces rejected; bootstrap
  policy names (`sg-tf-*`, `sg-ansible-*`) can never be declared here;
  `kv` keeps `prevent_destroy`.

### The tool boundary (`policies/bootstrap/`, written by Ansible in prompt 02)

Check the four policies against `00_01 §4` and tighten them if a capability
is missing or extra. In particular `sg-tf-platform` needs
`shift-gear/sys/mounts/*`, `shift-gear/sys/policies/acl/*`,
`shift-gear/auth/token/roles/*`, `sys/audit/*` (sudo) and the PKI/transit
config paths it manages; it must **not** have `sys/auth/*`,
`identity/*`, `kv/data/*` or delete on `kv`. `sg-ansible-platform` needs
`shift-gear/sys/auth/*`, `shift-gear/auth/*`, `shift-gear/identity/*`,
`shift-gear/kv/data/shift-gear/*`, `shift-gear/database/config/*`,
`shift-gear/database/roles/*`, `shift-gear/database/rotate-root/*` and
token creation through `sg-*` token roles; it must **not** have
`sys/mounts/*` writes or `sys/policies/*` writes. Every bootstrap policy
denies writes to `sg-tf-*` and `sg-ansible-*` policies.

### `make boundary` (`scripts/boundary-check.sh`)

Port golden_ticket's script: exactly **19** `sys/capabilities-self` checks
across the **four** bootstrap tokens (seal Vault and cluster), printed as
`token · allow|deny · capability · path` rows with expected vs actual. No
token value is ever printed. Include at least: Terraform cannot mint a
secret-id, enable an auth method, read KV data or delete `kv/`; Ansible
cannot create a mount or write a policy; neither can write a bootstrap
policy.

### `make check` (`scripts/check.sh`, static gate — no cluster required)

Now: `bash -n` + ShellCheck on every script; `terraform fmt -check`,
`validate` and `terraform test` **in every root** (tests live in
`terraform/<root>/tests/`); the `sg_stats` unit tests; the substrate grep
(lesson 19); `git ls-files` contains nothing under `.secrets/`, `.build/`,
no `*.tfstate*`. Prompt 06 adds `--syntax-check` and `ansible-lint`
(production profile).

## Validation

```sh
make lab && make lab              # second run: every plan empty, Ansible changed=0
make check                        # all PASS
make boundary                     # 19 rows, all as expected
vault namespace list              # shift-gear (VAULT_ADDR/VAULT_CACERT from the contract, token: tf-platform)
vault secrets list -namespace=shift-gear      # kv, transit, pki, pki-int, database
vault policy list -namespace=shift-gear       # sg-engineer … sg-agent-demo
vault audit list                              # file → stdout
# D11 proof: delete the vault_mount.kv block → apply → 403, kv/ still mounted → restore → plan clean
```

Record every output in the execution log.

## Out of scope

Auth methods and their roles, identity, KV data, the DB connection
(Ansible — prompts 04–06). VSO resources (prompt 05).

## Execution log

Appended by each run: what was done, deviations and why, validation output.
