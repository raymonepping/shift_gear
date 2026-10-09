# Testing

Every gate has a corresponding `make` target. All gates must pass before a release.

---

## Static gate: `make check`

```sh
make check
```

`scripts/check.sh` runs (no cluster required):

1. **`shellcheck`** — all `scripts/*.sh` files.
2. **`terraform fmt -check`** — all five roots.
3. **`terraform validate`** — all five roots (requires providers to be initialised; `make check`
   runs `terraform init -backend=false` first).
4. **Substrate grep** — enforces that `crc`, `vfkit`, `api.crc.testing`, `apps-crc.testing` do
   not appear outside `terraform/infra/` and `scripts/crc-*.sh`.
5. **Ansible collections** — `make deps` installs pinned collections into `.cache/ansible/collections/`.
6. **ansible-lint** — production profile, 0 failures; runs on all playbooks.
7. **Unit tests** — `terraform test` on any root that has a `tests/` directory.

Expected output: `check: 18/18 passed`.

---

## Full build: `make lab`

```sh
make lab
```

Runs all 13 phases then the three automatic gates. On failure, prints the resume command.
See [layers](layers.md) for per-phase details.

---

## Idempotency: `make idempotency`

```sh
make idempotency
```

Re-runs every Ansible phase with the same inventory and variables. Requires `changed=0` for
all tasks except those listed in `scripts/idempotency-allow.txt`.

Currently exempted (documented evidence-sync):
- `sg_ux` evidence ConfigMap sync (timestamp changes on each run).

Output: `.build/gates/idempotency.json` with `result: pass`.

---

## Drift: `make drift`

```sh
make drift
```

Two checks:

1. **Terraform** — `plan -detailed-exitcode` on all five roots. Exit code 0 = no changes.
   Exit code 2 = drift detected (unexpected changes).
2. **Ansible** — `--check` on all eight playbooks. `changed=0` required.

Output: `.build/gates/drift.json`.

---

## Secret scan: `make secret-scan`

```sh
make secret-scan
```

`scripts/secret-scan.sh` greps tracked files for:
- `hvs.` or `hvb.` or `hvr.` (Vault token prefixes)
- `-----BEGIN` (PEM key material)
- `02MMVV` (Vault Enterprise licence prefix)
- `VAULT_TOKEN=` assigned to a non-placeholder value

Expected: zero matches in tracked files.

Output: `.build/gates/secret-scan.json`.

---

## Token boundary: `make boundary`

```sh
make boundary
```

`scripts/boundary-check.sh` calls `sys/capabilities-self` with each bootstrap token against
19 paths — some that the token must be allowed, some it must be denied.

Example rows:

```
tf-seal          vault-seal  sys/mounts/transit                        allow:create  PASS
tf-seal          vault-seal  auth/approle/role/sg-seal-autounseal/secret-id  deny:update  PASS
ansible-platform vault       shift-gear/sys/mounts/transit             deny:create   PASS
```

Expected: 19/19 PASS.

---

## Rotation proof: `make rotation-proof`

```sh
make rotation-proof
```

`scripts/rotation-proof.sh`:

1. Reads the current secret-id from `seal-agent-approle` Secret.
2. Runs `make agent` (generates a new secret-id).
3. Proves the old secret-id returns `400`.
4. Proves the new secret-id returns `200`.
5. Proves only 1 valid accessor remains in Vault.
6. Runs `make agent` a second time; repeats the proof.

---

## Validation: `make validate`

```sh
make validate
```

Ansible `sg_validate` role. Read-only. Checks:

- Vault initialized and unsealed
- HA: 1 active node, 3 voters
- All platform mounts present (`kv/`, `transit/`, `pki-int/`, `database/`, `sys/audit`)
- All platform policies present
- Seal Vault healthy
- Vault UI Route answering
- Keycloak OIDC discovery answering
- VSO Secrets synced (`app-config`, `db-creds` in `sg-workloads`)
- Identity verify passthrough (reads `.build/identity-verify.json`)

Output: `.build/validation.json` and `.build/gates/validation.json`.

---

## Identity verify: `make identity-verify`

```sh
make identity-verify
```

Ansible `sg_identity_verify` role. For each persona (`ada`, `ben`, `cleo`, `dirk`, `finn`):

1. Authenticates via JWT (Keycloak token).
2. Authenticates via LDAP (username + password from Vault KV).
3. Calls `auth/token/lookup-self` on the resulting token.
4. Asserts that the token's policies match exactly the expected set.

Output: `.build/identity-verify.json`.

---

## Stack verify: `make verify`

```sh
make verify
```

`scripts/verify-stack.sh`. Shell-based checks:

- Cluster operators: 0 degraded
- Seal Vault: initialized and unsealed
- Vault HA: 1 active, 3 voters
- Vault licence: valid (> 30 days remaining)
- Seal agent: 1/1 available
- VSO CSV: Succeeded
- VSO Secrets present: `app-config`, `db-creds`
- Deployments available: `agent-demo`, `workload-a`, `workload-b`, `openldap`, `keycloak`
- Agent demo rendered its file
- Gate files: idempotency, drift, secret-scan, validation — all `result: pass`
- No `VAULT_*` env in workload/app pods

---

## Terraform tests

Each root that has a `tests/` directory runs `terraform test` as part of `make check`.

| Root | Test file | What it checks |
|---|---|---|
| `infra` | `tests/contract.tftest.hcl` | Output fields are non-empty strings |
| `platform` | `tests/policies.tftest.hcl` | Policy HCL parses without error |

Run a single root's tests:

```sh
cd terraform/infra && terraform test
```

---

## UI tests: `make ui-test`

```sh
make ui-test
```

Playwright + axe:

- Chromium headless
- Journeys: sign-in, Fleet, Layers, Engines, Routes, Pods, Operator, Ansible, Agent, Audit,
  Cluster
- axe WCAG 2.1 AA on every page
- Excludes `@failover` and `@screens` by default

```sh
make ui-test-failover     # @failover: kill vault-0 during the test; requires ENABLE_FAILOVER_TEST=true
make ui-screens           # screenshot every page → docs/screenshots/
make ui-check             # Nuxt typecheck + ESLint (no cluster required)
```

---

## Running all gates together

```sh
make lab                # builds everything + runs idempotency, secret-scan, boundary
make verify             # stack health
make drift              # drift detection
make identity-verify    # persona verification
make rotation-proof     # rotation proof
make validate           # Ansible validation report
make ui-test            # Playwright + axe
```

All of the above must pass before tagging a release. See `docs/release-checklist.md`.
