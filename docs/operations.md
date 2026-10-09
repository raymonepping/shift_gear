# Operations

---

## `make` targets

| Target | Description |
|---|---|
| `make lab` | Full 13-phase build in order + idempotency, secret-scan, boundary gates |
| `make check` | Static gate: ShellCheck, `terraform fmt -check`, `terraform validate`, substrate grep, unit tests |
| `make verify` | Full stack health: cluster operators, seal chain, Vault HA, licence, VSO, gates |
| `make drift` | Terraform `plan -detailed-exitcode` on all 5 roots + Ansible `--check` on all 8 playbooks |
| `make idempotency` | Re-run every Ansible phase; require `changed=0` (exceptions in `idempotency-allow.txt`) |
| `make boundary` | 19 `sys/capabilities-self` checks across all four bootstrap tokens |
| `make rotation-proof` | Rotate seal agent secret-id twice; prove old=400, current=200, count=1 |
| `make secret-scan` | Grep tracked files for token patterns, PEM headers, `hvs.`, licence prefix |
| `make identity-verify` | Every persona logs in through all auth methods and receives exactly their policies |
| `make layers` | Emit `.build/layers.json` — per-phase resource counts, Ansible stats, gate results |
| `make wl-a-rotate` | Write new KV version for `app-config`; VSO syncs within ~30 s; workload-a rolls |
| `make vso-status` | VSO CRD sync status and workload pod states |
| `make vault-roll` | Controlled rolling restart: standbys first, leader last; each waits for 3 voters |
| `make crc-up` | Start CRC (configure + start; idempotent) |
| `make crc-down` | Stop CRC (keeps VM + cluster data) |
| `make crc-delete` | Destroy CRC VM (keeps pull secret + cache) |
| `make crc-reset` | `crc-delete` + `crc-up` |
| `make crc-console` | Print console URL + kubeadmin credentials |
| `make up` | Bring the full stack up from stopped state (scale up deployments, unseal) |
| `make down` | Scale all workloads down gracefully (never deletes PVCs or `.secrets/`) |
| `make reset` | DESTRUCTIVE: delete namespaces + generated state (requires typing `shift-gear`) |
| `make infra` | Run only `tf infra apply` |
| `make foundation` | Run only `tf foundation apply` |
| `make workloads` | Run only `tf workloads apply` |
| `make seal` | Run only `tf seal apply` |
| `make platform` | Run only `tf platform apply` |
| `make prepare` | Run only `ansible prepare` |
| `make seal-init` | Run only `ansible seal-init` |
| `make agent` | Run only `ansible agent` |
| `make bootstrap` | Run only `ansible bootstrap` |
| `make identity` | Run only `ansible identity` |
| `make configure` | Run only `ansible configure` |
| `make ux` | Run only `ansible ux` |
| `make validate` | Run only `ansible validate` |
| `make unseal` | Unseal the seal Vault (1 share/threshold 1) |
| `make identity-show-user PERSON=ada` | Print person's password from Vault KV |
| `make trust` | Add the lab CA to the macOS System keychain (sudo) |
| `make untrust` | Remove the lab CA from the macOS System keychain (sudo) |
| `make trust-status` | Is the CA trusted? Does macOS accept shiftgear.apps-crc.testing? |
| `make ui-test` | Playwright + axe WCAG 2.1 AA gate |
| `make ui-screens` | Screenshot every screen → `docs/screenshots/` |
| `make ui-check` | Nuxt typecheck + ESLint |
| `make status` | Alias for `make verify` |
| `make deps` | Install pinned Ansible collections + check required tools |
| `make help` | List all targets with descriptions |

---

## Full lab workflow

### From nothing

```sh
make crc-reset     # destroy any previous CRC VM; provision + start fresh (~15–20 min)
make lab           # all 13 phases + 3 gates
```

**Indicative rebuild timings** (single Mac M-series, CRC 4.22):

| Phase | Tool | ~Duration |
|---|---|---|
| infra | tf | 30 s |
| foundation | tf | 2 min |
| prepare | ansible | 3 min |
| workloads | tf | 8 min |
| seal-init | ansible | 1 min |
| seal | tf | 30 s |
| agent | ansible | 30 s |
| bootstrap | ansible | 2 min |
| platform | tf | 1 min |
| identity | ansible | 4 min |
| configure | ansible | 2 min |
| ux | ansible | 3 min |
| validate | ansible | 1 min |
| gates | — | 3 min |
| **Total** | | **~31 min** |

### Second `make lab`

Every `terraform plan` exits 0. Every Ansible phase reports `changed=0` except:

- `sg_ux` evidence sync (the `.build/layers.json` timestamp changes).

This is documented in `idempotency-allow.txt`.

---

## Cold start

If the Mac was asleep and CRC is stopped:

```sh
make crc-up        # restarts the CRC VM (~3–5 min)
make up            # scale up deployments, unseal seal Vault, verify
```

`make up` calls `scripts/down.sh up` which:
1. Scales all Deployments in `sg-vault`, `sg-vault-seal`, `sg-identity`, `sg-workloads`, `sg-app`
   to their desired replica counts.
2. Calls `make unseal` (ansible unseal) to unseal the seal Vault if sealed.
3. Calls `make verify` to confirm the stack is healthy.

---

## Unseal

The cluster Vault unseals itself automatically via the transit seal (no operator action required).
The seal Vault uses Shamir (1 share, threshold 1). If the seal Vault pod restarts:

```sh
make unseal
```

This runs `ansible/unseal.yml` which reads the unseal key from `.secrets/` and calls
`sys/unseal` on the seal Vault.

---

## TLS certificate rotation

TLS certs are generated by `scripts/tls.sh` and are valid for 365 days. To rotate:

```sh
rm .secrets/tls/vault.crt .secrets/tls/vault.key   # (or any cert to rotate)
make prepare           # regenerates missing certs; updates Kubernetes Secrets
make vault-roll        # rolling restart to pick up new certs
```

The CA is valid for 3650 days. Rotating the CA requires regenerating all leaf certs and
updating the Keycloak truststore — do this with `rm .secrets/tls/ca.key .secrets/tls/pub/ca.pem`
followed by a full `make prepare && make vault-roll`.

---

## Seal agent secret-id rotation

The rotator CronJob rotates the seal agent's AppRole secret-id every 24 hours. To rotate
manually:

```sh
make agent         # runs sg_seal_agent; generates a new secret-id and restarts the seal-agent pod
```

To prove rotation:

```sh
make rotation-proof
```

Output:
- Old secret-id: `400 Permission Denied`
- Current secret-id: `200 OK`
- Count in Vault: `1`

---

## Dynamic lease renewal (VSO)

`VaultDynamicSecret` resources have `renewalPercent: 80`. VSO renews the PostgreSQL credential
at 80% of TTL. If the lease lapses (e.g., after a long Mac sleep):

```sh
make vso-status       # shows lastSyncTime and error if any
```

VSO will automatically request a new credential on the next sync cycle. If it does not
recover within 2 minutes:

```sh
oc -n sg-workloads delete secret db-creds   # VSO re-creates it immediately
```

---

## Bootstrap token renewal

Bootstrap tokens have a 72-hour TTL. They are renewed by `lab.sh` before each phase if less
than 24 hours remain. To renew manually:

```sh
vault token renew "$(cat .secrets/tokens/tf-platform)"      # requires the token itself
```

To mint new bootstrap tokens from scratch, re-run `make seal-init` and `make bootstrap`.
This is only required if the tokens are expired.

---

## Adding a phase

1. Add a line to `scripts/phases.txt`: `tf <root>` or `ansible <playbook>`.
2. For a Terraform root: create `terraform/<root>/` with `main.tf`, `variables.tf`, `outputs.tf`,
   and a `tests/` directory. Set `backend "local" { path = "../../.secrets/terraform/<root>/..." }`.
3. For an Ansible playbook: create `ansible/<playbook>.yml` and any roles in `ansible/roles/`.
4. Run `make check` — the substrate grep and `terraform validate` run on all roots.

---

## Adding a policy

1. Create `policies/platform/<name>.hcl`.
2. Add it to `terraform/platform/main.tf` as a `vault_policy` resource.
3. Add it to `ansible/roles/sg_validate/vars/main.yml` in `sg_validate_platform_policies`.
4. Run `make platform` then `make validate`.

---

## Adding a VSO resource

1. Never add VSO resources before the VSO CSV `phase=Succeeded`. The `prepare` phase waits.
2. Add `VaultStaticSecret` or `VaultDynamicSecret` resources to `terraform/workloads/main.tf`.
3. Add the corresponding Vault path to `sg-vso` policy in `policies/platform/sg-vso.hcl`.
4. Run `make workloads` then `make vso-status`.

---

## Rotating the Vault Enterprise licence

```sh
# Update VAULT_LICENSE in .env
make prepare           # re-creates the vault-license Secret in all Vault namespaces
make vault-roll        # rolling restart to reload the licence
make verify            # confirm licence expiry > 30 days
```

---

## Upgrading VSO

1. Update the `channel` or `startingCSV` in `terraform/foundation/main.tf` (the
   `vault-secrets-operator` Subscription resource).
2. Run `make foundation`.
3. Wait for the CSV to reach `Succeeded`:
   ```sh
   oc -n openshift-operators get csv -w
   ```
4. Run `make vso-status` to confirm all CRDs still sync.

---

## Resilience proof tables

### Scenario 01 — Kill the active Vault pod

| Step | Expected | Verified |
|---|---|---|
| `oc -n sg-vault delete pod vault-0` | Pod terminates | ✓ |
| Raft elects new leader (vault-1 or vault-2) | HA status: 1 active, 2 voters → 3 voters when vault-0 rejoins | ✓ |
| `make verify` | All ✓ | ✓ |

### Scenario 02 — Restart the seal agent

| Step | Expected | Verified |
|---|---|---|
| `oc -n sg-vault-seal delete pod -l app=seal-agent` | Pod restarts, re-authenticates with AppRole | ✓ |
| Cluster Vault: no sealing observed | Vault uses transit seal; seal agent restart does not seal the cluster | ✓ |
| `make verify` | All ✓ | ✓ |

### Scenario 06 — Static secret rotation

| Step | Expected | Verified |
|---|---|---|
| `make wl-a-rotate` | New KV version written | ✓ |
| VSO syncs `app-config` Secret within 30 s | `lastSyncTime` updated | ✓ |
| workload-a rolls automatically | New pod reads new value | ✓ |

### Scenario 07 — Dynamic credential revoked

| Step | Expected | Verified |
|---|---|---|
| `vault lease revoke <lease>` in `database/creds/demo-reader` | Lease revoked | ✓ |
| VSO requests new credential within `renewalPercent` cycle | New `db-creds` Secret created | ✓ |
| workload-b continues running | Reads new credential | ✓ |

### Drift detection

| Tool | Change made | Detected by |
|---|---|---|
| Terraform | `oc edit deployment vault-0` (add label) | `make drift` (tf plan shows diff) |
| Ansible | LDAP group member added via `ldapmodify` | `make drift` (ansible check-mode reports change) |
| VSO | `Secret` content edited manually | `make verify` (`VaultStaticSecret.status.lastSyncTime` check) |
