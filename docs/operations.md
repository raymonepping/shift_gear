# Operations

---

## `make` targets

| Target | Description |
|---|---|
| `make lab-times` | Print the last phase/gate timing table without running the lab |
| `make ui-test-failover` | Run the explicitly enabled Playwright leader-deletion journey |
| `make lab` | Full 13-phase build in order + idempotency, Terraform drift, secret-scan gates |
| `make check` | Static gate: ShellCheck, `terraform fmt -check`, `terraform validate`, substrate grep, unit tests |
| `make verify` | Full stack health: cluster operators, seal chain, Vault HA, licence, VSO, gates |
| `make drift` | Terraform `plan -detailed-exitcode` on all 5 roots + Ansible `--check` on all 8 playbooks |
| `make idempotency` | Re-run every Ansible phase; require `changed=0` (exceptions in `idempotency-allow.txt`) |
| `make boundary` | 19 `sys/capabilities-self` checks across all four bootstrap tokens |
| `make rotation-proof` | Rotate seal agent secret-id twice; prove previous ID absent, current lookup=200, count=1 |
| `make secret-scan` | Scan evidence, cached logs, state and tracked files for known secret values and token/key/licence patterns; check state modes |
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
| `make reset` | DESTRUCTIVE: archive generated state and delete namespaces (requires typing `shift-gear`) |
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
DRY_RUN=1 make reset             # review generated state to archive
CONFIRM=shift-gear make reset    # destructive: archive state and delete lab namespaces
make crc-reset                  # destructive: replace the CRC VM
make lab           # all 13 phases + 3 gates
```

The rebuild was measured on 2026-10-10 on a 12-core Apple M4 Pro MacBook Pro with 48 GB RAM. CRC used 8 vCPU and 24,576 MB RAM. Creating the fresh CRC VM took 3m18s. The first `make lab` recorded 9m00s in `.cache/convergence-from-nothing.json`; its final evidence republish brought the command's wall time to 9m59s, so `make crc-reset && make lab` took 13m17s end to end. The adjacent re-run is the independent second `make lab`, finished 2026-10-10T16:44:37Z. `make lab-times` prints the phase and gate values from the latest run.

| Phase or gate | Tool | Rebuild from nothing | Converged re-run |
| --- | --- | --- | --- |
| infra | Terraform | 0m03s | 0m03s |
| foundation | Terraform | 0m05s | 0m03s |
| prepare | Ansible | 0m16s | 0m05s |
| workloads | Terraform | 0m20s | 0m03s |
| seal-init | Ansible | 0m19s | 0m06s |
| seal | Terraform | 0m01s | 0m01s |
| agent | Ansible | 0m13s | 0m11s |
| bootstrap | Ansible | 0m36s | 0m10s |
| platform | Terraform | 0m03s | 0m01s |
| identity | Ansible | 1m13s | 0m31s |
| configure | Ansible | 0m29s | 0m10s |
| ux | Ansible | 2m11s | 0m59s |
| validate | Ansible | 0m11s | 0m11s |
| idempotency | Gate | 2m50s | 2m28s |
| drift | Gate | 0m07s | 0m06s |
| secret-scan | Gate | 0m02s | 0m03s |
| Total | Recorded `make lab` time | 9m00s | 5m11s |

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

The `seal-rotator` CronJob runs every six hours (`0 */6 * * *`). The
`sg-seal-autounseal` secret-id expires after 24 hours and permits repeated logins
(`secret_id_num_uses = 0`). `make agent` reuses an existing valid ID; it is not a
command to force rotation.

```sh
make rotation-proof
```

The proof runs two Jobs from the CronJob, checks that the agent holds a new ID,
checks that the previous ID is absent and the current lookup returns 200, and
requires exactly one ID. Controller logins cannot prove this because the role
is bound to the cluster pod CIDR. The non-expiring rotator secret-id is a
separate credential held in `seal-rotator-approle`.

---

## Dynamic lease renewal (VSO)

`VaultDynamicSecret` resources have `renewalPercent: 67`. VSO renews the PostgreSQL credential
at 67% of TTL. If the lease lapses (e.g., after a long Mac sleep):

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

Bootstrap tokens are periodic orphan tokens with a 24-hour period. The
`seal-init` and `bootstrap` phases check existing tokens, reissue missing or
refused tokens through their policy-specific roles, and renew valid tokens on
every real run. Renewal is maintenance (`changed_when: false`), not a timed
pre-phase action in `lab.sh`.

```sh
make seal-init
make bootstrap
```

The bootstrap tasks use the locally retained root tokens to reconcile bootstrap
policies and token roles and issue replacement tokens. Routine Terraform and
configuration work use their scoped tokens.

---

## KV rotation add-on

`make rotation-up` / `make rotation-down` install and remove the add-on
without touching the 13 phases ([rotation](rotation.md)). With it installed:

- `make down` scales `sg-rotation` to 0 before Vault;
- `make up` scales it back after `sg-app`;
- `make reset` deletes `sg-rotation`;
- `make lab` leaves it alone. A `make lab` run with the add-on installed was
  idempotent with every plan empty (2026-10-28).

After a long pause, run `make up` first: `rotation-up` refuses expired
platform bootstrap tokens instead of refreshing them.

Measured in the recorded proof run of 2026-10-29 (prompt 03_01, all 14 steps
green; `.build/addons/rotation/proof-run.json`):
- `rotation-up` from removed: 86.4 s, and 86.0 s after a removal with overdue
  secrets (it waits to observe one 60 s rotation);
- a second `rotation-up`: 57.9 s, Terraform `No changes`, Ansible `changed=0`;
- `rotation-down`: 51.3 s (17 resources destroyed; it prints the kept
  secrets and a core drift check);
- `rotation-test`: 8.5 min (13 of 13 plus the leak check);
- Secure Door: `rotation-consumer-up` 12.7 s on a converged lab,
  `rotation-consumer-test` 6.8 min (10 of 10 plus the leak check);
- `make lab` with the add-on installed: 7.0 and 6.4 min, second run clean;
  without it: 6.4 and 5.7 min;
- `make down` 8.1 s, `make up` 4.3 min; both add-ons came back and
  `api-key/demo` continued v841 → v842 with no gap in its history;
- `make ui-test`: 10.7 min without the add-on (157 passed, 15 skipped),
  12.2 min with it (169 passed, 3 skipped).

`make up` restarts `agent-demo` when its init auth is still backing off from
the sealed interval. It deletes the pod instead of `rollout restart`: the
Deployment belongs to Terraform, and a `restartedAt` annotation on its
template was reported as drift by `make drift` (found by the 03_01 run).

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

| Step | Expected | Current review |
|---|---|---|
| Delete the active Vault pod | Pod terminates | PASS; the running leader was deleted |
| Raft elects a different leader | HA status returns to 1 active and 3 voters | PASS; replacement leader differed and the deleted pod rejoined |
| `make verify` | All ✓ | PASS, 22/22 |

### Scenario 02 — Restart the seal agent

| Step | Expected | Current review |
|---|---|---|
| Delete the seal-agent pod | Pod restarts, re-authenticates with AppRole | PASS; replacement pod UID observed |
| Cluster Vault: no sealing observed | Vault uses transit seal; seal agent restart does not seal the cluster | PASS; authenticated health remained available |
| `make verify` | All ✓ | PASS, 22/22 |

### Scenario 06 — Static secret rotation

| Step | Expected | Current review |
|---|---|---|
| `make wl-a-rotate` | New KV version written | PASS |
| VSO syncs `app-config` Secret within 30 s | `lastSyncTime` updated | PASS |
| workload-a rolls automatically | New pod reads new value | PASS; scenario completed in 21 s |

### Scenario 07 — Dynamic credential revoked

| Step | Expected | Current review |
|---|---|---|
| Revoke the exact `database/creds/demo-reader` lease | Lease revoked through the scoped path | PASS; broader revoke paths remained denied |
| VSO requests new credential within `renewalPercent` cycle | New `db-creds` Secret created | PASS; username changed and the old PostgreSQL role disappeared |
| workload-b continues running | Reads new credential | PASS; scenario completed in 148 s |

### Drift detection

| Tool | Change made | Detected by |
|---|---|---|
| Terraform | `oc -n sg-workloads edit deployment workload-a` (add a label) | `make drift` (tf plan shows diff) |
| Ansible | sg-cli client name changed | Identity check mode reports change; LDAP membership is tested by fresh login in scenario 08 |
| VSO | `app-config` Secret edited manually | Scenario 09 compared data hashes; VSO restored the Vault value after 6 s |

## Scenario inventory

| Scenario | What the script exercises |
| --- | --- |
| 01 | Active pod deletion and unsealed rejoin |
| 02 | Seal-agent restart with cluster health probes |
| 03 | Two rotator Jobs and secret-id lookup/list |
| 04 | Seal-Vault restart and manual unseal |
| 05 | Full down/up including VM stop/start |
| 06 | KV source rotation, Secret sync and workload-a rollout |
| 07 | Dynamic credential replacement and old-role removal |
| 08 | Four reversible drift mutations with detection and restoration checks |
| 09 | Hand-edit app-config; VSO restored the Vault value in 6 s in the proof run |

All nine scenarios passed on 2026-10-09/10. Timings and key evidence are recorded in roadmap 03_01.

## Run identity and publication recovery

All supported mutation wrappers and scenarios share a target lock across checkouts. Nested Ansible/Node workers retain the owning run's authority even when they close inherited file descriptors; an unrelated process cannot acquire the held lock. A competing command exits 75 before mutation.

The current attempt is `.build/run.json`, with a unique run ID, Kubernetes cluster UID, source revision/dirty flag, input digest, phase states and separate provisioning/publication results. The digest covers Terraform, Ansible, deployment templates, policies, scripts, collector, UI, scenarios, tests and workflows using relative paths and bytes. Generated state, credentials, dependencies and reports are excluded. Changes during a lab run fail convergence; keep inputs stable while testing.

A failed attempt does not overwrite `.build/last-success.json`. A separate safe `run.json` ConfigMap key lets the console show the latest recorded attempt beside its dated observation. Publication requires API access and the kubelet's mount refresh; if status publication itself fails, the host record remains authoritative and the command reports it. The console cannot know about an unpublished host failure.

If provisioning passed and final publication failed, use `make publish-evidence`; it verifies the live cluster UID and republishes UX/status without reapplying infrastructure. It refuses an incomplete provisioning run or another cluster. Existing snapshot reloads retain the original observation timestamp and become stale after 120 seconds; `make ux` creates a new observation. The seal-chain indicator and diagrams independently use live, read-only checks every 15 seconds while the tab is visible, with a 30-second freshness limit; an old snapshot cannot keep them green. See [runtime observation](runtime-observation.md). Missing, malformed, mixed-generation or future-dated observations cannot establish healthy current state.

The console's application rotation returns write acceptance with a KV version and operation ID. It remains **accepted-unverified** until delivery can be independently correlated; a snapshot refresh alone cannot prove VSO delivery. Repeating the same operation ID in the session returns its receipt. A CAS conflict requires reloading before a new operation. A transport timeout is uncertain and does not authorize an automatic new write. Agent re-injection is explicitly unavailable; use the host runbook for lifecycle operations.

See [credential operations](credential-operations.md), [session contract](session-contract.md), [field ownership](ownership.md) and the [Must delivery record](must-progress.md) for custody, access and actual verification status.
