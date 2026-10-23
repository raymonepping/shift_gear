# Testing

Every gate has a corresponding `make` target. All gates must pass before a release.

---

## Static gate: `make check`

```sh
make check
```

`scripts/check.sh` runs (no cluster required):

1. **Shell syntax and `shellcheck`** — all `scripts/*.sh` files.
2. **`terraform fmt -check`** — all five roots.
3. **`terraform validate`** — all five roots (requires providers to be initialised; `make check`
   runs `terraform init -backend=false` first).
4. **Substrate grep** — enforces that `crc`, `vfkit`, `api.crc.testing`, `apps-crc.testing` do
   not appear outside `terraform/infra/` and `scripts/crc-*.sh`.
5. **Ansible collections** — `make deps` installs pinned collections into `.cache/ansible/collections/`.
6. **ansible-lint** — production profile, 0 failures; runs on all playbooks.
7. **Unit tests** — `terraform test` on every root with tests, plus the Python `sg_stats` callback tests.

Recorded static result on 2026-10-09: `18 checks passed, 0 failed`.

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
all tasks except the exact named exceptions in `scripts/idempotency-tasks.json`.

Currently exempted (documented evidence-sync):
- `sg_ux : Sync the evidence ConfigMap (the console mounts it read-only)` (timestamp changes on each run). Any other changed UX task fails.

Output: `.build/gates/idempotency.json` with `result: pass`.

---

## Drift: `make drift`

```sh
make drift
```

Two checks:

1. **Terraform** — `plan -detailed-exitcode` on all five roots. Exit code 0 = no changes.
   Exit code 2 = drift detected (unexpected changes).
2. **Ansible** — `--check` on all eight playbooks. `changed=0` required, except phases
   explicitly named in `scripts/idempotency-tasks.json` (currently the single UX evidence publication task).

Output: `.build/gates/drift.json`.

---

## Secret scan: `make secret-scan`

```sh
make secret-scan
```

`scripts/secret-scan.sh` checks known generated secrets and three patterns:

- Vault service, batch and recovery token prefixes with a token-sized suffix
- The Vault Enterprise licence header
- PEM private-key headers followed by a base64 body

The live scan covers `.build/`, recursive cached logs, current Terraform states, and tracked/untracked non-ignored delivery files. Required KV and AppRole source reads fail closed. It checks known generated values and secret-shaped patterns, then verifies current state permissions are 0600. Historical state backups remain confidential custody material; their private inventory is not a claim that they contain no credentials. See the strengthening gates below for exact public metadata exemptions.

Output: `.build/gates/secret-scan.json`.

---

## Token boundary: `make boundary`

```sh
make boundary
```

`scripts/boundary-check.sh` calls `sys/capabilities-self` with each bootstrap token against
19 token/path/operation assertions — some that the token must be allowed, some it must be denied.

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

The script runs two Jobs from `seal-rotator`, verifies the agent holds a new
secret-id, checks the previous ID is absent, checks current-ID lookup returns
200, and requires exactly one ID. It uses Ansible’s seal token for lookup and
list. It does not test login from the controller, which is outside the role’s
pod-CIDR binding. See scenario 03 for the precise credential settings.

---

## Validation: `make validate`

```sh
make validate
```

Ansible `sg_validate` role. Read-only. Checks:

- Vault initialized and unsealed
- HA: 1 active node, 3 voters
- All platform mounts present (`kv/`, `transit/`, `pki/`, `pki-int/`, `database/`)
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
- Deployments available: `sg-ui`, `agent-demo`, `workload-a`, `workload-b`, `postgres`, `openldap`, `keycloak`
- Keycloak root redirects to the application `/signin` page
- Agent demo rendered its file and the application cannot see either Agent token-sink path
- Gate files: idempotency, drift and secret-scan require `result: pass`; validation requires `fail_count: 0` and positive `pass_count`
- No environment names containing `VAULT` in Running workload/app pod specs; `sg-ui` and `vault-agent*` containers are named exceptions. The check also inspects Vault-named `envFrom` sources, not their contents or mounted token files.

---

## Terraform tests

Each root that has a `tests/` directory runs `terraform test` as part of `make check`.

| Root | Test file | What it checks |
|---|---|---|
| `infra` | `tests/contract.tftest.hcl` | Output fields are non-empty strings |
| `foundation` | `tests/namespaces.tftest.hcl` | Namespace and resource shape |
| `workloads` | `tests/workloads.tftest.hcl` | Workload resource shape |
| `seal` | `tests/seal.tftest.hcl` | AppRole and seal structure |
| `platform` | `tests/platform.tftest.hcl` | Platform structure, policy inputs and audit devices |

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

- Desktop Chromium and mobile-chrome projects
- Browser contexts verify TLS; the run fails when the router or project CA is not trusted by the host.
- Journeys: sign-in, Fleet, Layers, Engines, Routes, Pods, Operator, Ansible, Agent, Audit,
  Cluster
- axe WCAG 2.1 AA on every page
- Excludes `@failover` and `@screens` by default

```sh
make ui-test-failover     # @failover: identify and delete the active Vault pod
make ui-screens           # screenshot every page → docs/screenshots/
make ui-check             # Nuxt typecheck + ESLint (no cluster required)
```

---

## Running all gates together

```sh
make lab                # builds everything + runs idempotency, Terraform drift, secret-scan
make verify             # runtime health + current source/cluster/run convergence
make drift              # drift detection
make identity-verify    # persona verification
make rotation-proof     # rotation proof
make validate           # Ansible validation report
make ui-test            # Playwright + axe
```

All of the above must pass before tagging a release. See `docs/release-checklist.md`.

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

Run results and timings from 2026-10-09 are recorded in roadmap 03_01.

## Strengthening release gates (2026-10-14)

`make must-test` exercises malformed/future/stale evidence, nested snapshot corruption, capability mapping, signed logout claims, KV field preservation, bounded collector input/projection, credential-bearing computed state, exact changed-task exceptions, relocation-stable digests, lock exclusion/inheritance and incomplete release receipts. It uses Ansible's Python so controller dependencies are consistent. `make ui-check` remains the type and lint gate.

The browser suite now checks direct authorization and unchanged KV metadata after forbidden writes, accepted/unverified rotation receipts, concurrent CAS version ordering, a second session invalidated through actual provider logout, and document containment after data loads at 390, 320 and 195 CSS pixels. The last viewport models the effective width of a 390px screen at 200% zoom; it does not claim native browser zoom behavior was measured. Browser TLS verification stays enabled. Failure screenshots and saved authentication states remain private, ignored artifacts.

`make proof-manifest` runs the credential-free checks and writes a sanitized `.build/proof-manifest.json`. `make proof-live` additionally runs credential expiry and same-root certificate renewal, two labs, full drift, verification, boundaries, identity, standard/failover browsers, screenshots, scenarios 01–09 (cold-start last), and final convergence/drift. Recovery/restore remains explicitly deferred. Each receipt binds the actual source revision, dirty flag, input digest, target/run identity, step exits and overall result. A failed or changed-input run cannot become a passing receipt. Logs stay under `.cache/proofs/<proof-id>/`; publish only reviewed, sanitized artifacts.

GitHub's Quality contracts workflow is credential-free. Protected live proof runs only on the dedicated `shift-gear-lab` runner/environment, requires an operator-reviewed clean checkout at the requested revision, and retains only the sanitized receipt for 14 days. Tag release creation now requires a successful protected live workflow and a receipt matching the tagged revision, source digest and complete live ladder. A local dirty working-tree receipt is useful diagnosis but is rejected for release. Workflow configuration is not evidence that GitHub has executed it.

The scanner recursively inventories required live KV/AppRole sources, current state, tracked/untracked delivery files and generated evidence/logs. Failure to read a required source fails the scan. `SG_SCAN_MODE=offline` explicitly limits coverage; it cannot be represented as a live scan. Only the exact public `app_name=shift-gear` and demo `demo_feature_flag=agent-sidecar-demo` seed values at their named paths, plus correctly shaped app-config rotation UUID/timestamp metadata, are exempt; new/other fields remain secret by default. Historical state and private TLS backups remain confidential custody material, not credential-free deliverables.

`make verify` requires successful provisioning for the current source digest and cluster, plus passing gates bound to that run. `VERIFY_SCOPE=runtime make verify` checks runtime health only and explicitly reports that convergence gates were not evaluated. Certificate and cold-start drills use that narrower check before the final full convergence run.

On macOS, the proof controller holds a `caffeinate -ims` assertion for its own lifetime to prevent idle sleep from pausing the lab VM. Live proof checks and repairs the node clock before starting; an unreachable API fails preflight. Explicit host sleep/lid closure can still interrupt a run: repair time and rerun the proof rather than accepting future-dated observations or extending timestamp tolerances.


## Completed Must acceptance (2026-10-15)

Local live proof `f3a2a3db-fd21-4c5c-8584-06050379c4c5` passed all 36 steps against input digest `74dcea050ef52bb5284723c9010c25e02c956aa95c9e4d0265c7983e58933c32`. This includes 18 static checks, 33 offline regressions, UI type/lint, 120 desktop/mobile browser tests, one separate browser failover, two screenshot journeys, all nine scenarios with full verification after each, and final lab/drift. Stack and boundary checks passed 23/23 and 19/19 respectively. The receipt records `dirty=true`; it is local acceptance evidence and cannot authorize a protected release. Recovery M06 remains owner-deferred. See the [delivery record](must-progress.md) for exact identities, private log locations and operational limits.

## Selected Should gates (2026-10-16)

The selected S01/S02/S05/S06 increment adds `make component-proof`, `make observer-boundary`, `make destruction-guard-proof`, `make upgrade-proof` and `make dependency-inventory` to the protected ladder, bringing it to 41 steps. The existing 36-step receipt remains historical evidence for the prior Must implementation; it cannot certify changed sources. The release verifier now requires the new targets too.

Offline tests include real local HTTPS response limits, absolute deadlines and certificate rejection; independent source-state/projection contracts; and immutable image-catalog rejection. Browser tests add runtime-source investigation, actual eleven-source observations (including five seal-chain sources), audit filtering/paging/restart and keyboard use on desktop/mobile. New workflows are documented in [runtime observation](runtime-observation.md), [PKI/Transit proofs](vault-component-proofs.md) and [dependency operations](dependency-operations.md). Current acceptance is tracked separately in the [Should delivery record](should-progress.md).

Selected Should local acceptance passed all 41 ordered live steps on 2026-10-16, proof `209adbc4-ca55-41ae-9b6a-168dce3f8db8`, including 130 standard browser tests and the separate live failover. The [final delivery record](should-progress.md#final-local-acceptance--2026-10-16) contains the exact digest, cluster/run identity, screenshot review and remaining recovery/runtime/release limits.

## C04 explorer coverage (2026-10-17)

The explorer adds two producer tests and two UI projection tests, bringing offline regressions to 45 (27 Python, 13 UI/HTTPS, five collector). Four explorer browser journeys run on desktop and mobile; the standard suite now contains 138 tests. The page is included in both-persona axe scans and the 390/320/195 CSS-pixel containment loop. Screenshot journeys include `/explorer` at desktop and mobile widths, bringing captures to 28. Tests distinguish Origin refusal from explicit write-method refusal and compare the published registries and their exact source-file hashes. See the [C04 delivery record](c04-progress.md) for results rather than assuming an earlier receipt certifies changed sources.

C04 local acceptance passed the complete 41-step ladder on unchanged inputs: proof `c32efda8-30e3-42e8-8c80-2a20e1f59c24`, 138/138 standard browsers, separate live failover, all nine scenarios and final idempotent convergence/drift. See the [final C04 record](c04-progress.md#final-local-acceptance--2026-10-17) for the exact input digest, final run/cluster identity, retained failed attempt and visual review. The receipt is local and dirty; it does not authorize a protected release.

C02/C03 add `make observability-proof` (private scrape/access boundaries, actual retained redaction and pod continuity) and `make consumer-proof` (actual database and identity isolation, lease replacement/retirement and pod recovery). Both invalidate an old receipt at start and bind results to unchanged sources. The full live ladder now includes these gates; historical 41-step results refer to earlier sources. Browser coverage includes independent observability failures/freshness, API restrictions, keyboard navigation, Agent cards, axe and 195/320/390px containment. See [current acceptance status](c02-c03-progress.md).

Optional telemetry mode checks cover default-off shape (no backend deployments/PVCs or archive mount), preferred OpenTelemetry collection with original timestamps, Prometheus alternative, and disabled runtime/browser behavior with existing data retained. Runtime-only health checks do not replace the final full convergence gates. The live manifest records its selected optional configuration so a disabled-mode pass is not misread as enabled export proof.

Seal-chain regression coverage includes valid negative Vault health codes, malformed health and Agent metadata, partial/unreachable sources, expired/future timestamps, Agent readiness and inconsistent leadership. Browser checks cover Agent failure/recovery, transport failure/recovery, retained-response expiry, and a real 125-second sampling window with a deliberately stale snapshot. `make observer-boundary` checks twenty named allow/deny cases across both observation namespaces. These targeted checks do not replace the source-bound full release ladder.
