# Frontend 02_01 — Playwright journeys + accessibility gate

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

The UI runs at `https://shiftgear.{{ sg_apps_domain }}` — read from the
cluster contract; never hardcoded in tests. Template:
- `../golden_ticket/ux/e2e/` — the most recent reference; reuse test
  structure, helpers, and axe setup directly.
- `../red_pass/ux/tests/` — Playwright setup, persona auth, global setup.
- `../red_doors/ui/tests/` — real OIDC via Keycloak, saved `storageState`
  per persona, screenshot spec, `@failover` test.

Nothing is mocked: the journeys drive real Vault and OpenShift state.

Apply: lesson from Red Doors `02_01` execution log — the API's DB renewal
must check the wall clock (not only `setTimeout`) to survive Mac sleep.

## Deliverables (`ui/tests/`, `ui/playwright.config.ts`)

### Auth setup

- `global-setup.ts`: sign in once per persona (`ada`, `ben`, `cleo`, `finn`)
  through `/auth/login` → Keycloak → callback; passwords read at runtime
  from Vault KV by the Make target (`scripts/identity-show-user.sh`,
  golden_ticket's `ui-signin-test.sh` pattern) into the test process's
  environment only — never written to disk, never hardcoded, never
  committed (`tests/.auth/` gitignored).
- Trust: `ignoreHTTPSErrors: true` for `*.{{ sg_apps_domain }}` Routes
  (OpenShift Local's ingress CA is not in the system trust store; document
  it in the config).
- `BASE_URL` is read from the environment; the Make target sets it to
  `https://shiftgear.<apps_domain>` from `.build/terraform/infra.json`. No
  domain literal anywhere in the tests — the same suite runs against any
  substrate.

### `fleet.spec.ts` (was `dashboard.spec.ts`)

- `ada`: all five stat tiles present and non-empty (Pods, Vault Secured,
  Raft Voters, Reachable, Compute). Each value is a number > 0.
- Seal chain diagram visible: `vault-seal-0`, `seal-agent`, `vault-0/1/2`
  all rendered with status text.
- Seal chain pill in topbar reads `● Seal chain 3/3`.
- `cleo`: Rotate button visible on the Operator summary tile.
- `finn`: Rotate buttons absent; Audit link in sidebar accessible.
- Tile provenance labels present: each stat tile shows its evidence source
  (e.g. "from Terraform workloads", "from make validate").

### `operator.spec.ts`

- `cleo`: trigger rotation of `app-config` VaultStaticSecret → assert the
  "syncing…" spinner appears → assert `last_sync_time` updates within 35s →
  assert `workload-a` has restarted (replica count unchanged, new pod age < 60s).
- `ada`: rotation button absent (engineers cannot rotate).
- `finn`: Operator panel is read-only (no buttons); all data visible.
- Assert workload-b's Secret `db-creds` exists and has label
  `managed-by=hashicorp-vso`.

### `layers.spec.ts` (was `layer-diagram.spec.ts`)

- Hero summary line contains `Terraform` and `Ansible` and a phase count.
- **Gates**: all four gate cards (Idempotency, Drift, Secret scan, Validation)
  are present; each shows a `● pass` pill.
- Each gate card shows the script name (e.g. `scripts/drift.sh`) and a
  timestamp that is a parseable ISO date.
- **Phases**: at least 4 phase rows; each row shows a tool badge (Terraform
  or Ansible), a phase name, and a status pill.
- Automation digest line is present and contains a hex substring.
- Clicking a phase row expands a detail panel (does not throw).

### `engines.spec.ts`

- Mounted engines section contains at least the cards: Key/Value, Transit,
  PKI, Database.
- Each card shows `● Live` and a mount path.
- "Not mounted, on purpose" section is present; at least one row visible.
- `ada` (engineer): page fully readable; no action buttons.

### `pods.spec.ts`

- At least 5 pod cards visible.
- Each card has exactly four indicator cells.
- At least one card has role badge `CLUSTER · LEADER`.
- Exactly one card has role badge `SEAL VAULT`.
- Each card shows a `● Reachable` or `● Unreachable` pill.
- Clicking a `PROVISIONED` indicator expands the evidence panel showing a
  Terraform resource reference.

### `routes.spec.ts`

- At least 5 route rows visible.
- Each row has a clickable URL that is a valid `https://` address.
- Each row shows a TLS termination badge: `Passthrough`, `Edge`, or `Re-encrypt`.
- At least one row has the label "Vault — UI, API, writes (active node)" and
  a backend pill marked as leader.
- The `vault-active` row shows exactly one pod marked leader.
- All backend pills are **green** (no amber or red on a healthy system).
- `ada` (engineer): page fully readable; no action buttons.

### `ansible.spec.ts`

- `ada`: Ansible panel shows the last validate run with at least one ✓ item.
- `cleo`: "Run validate now" button is present and triggers a new run
  (assert that the timestamp changes after the run completes, max 60s).
- `finn`: read-only view; no run button.

### `agent.spec.ts`

- `ada`: Agent panel shows injection timestamp and at least one key name.
- Token TTL countdown is present and is a number > 0.
- `cleo`: "Trigger re-injection" button visible.
- `finn`: read-only.

### `cluster.spec.ts`

- 3 nodes visible, exactly one labelled "Leader".
- Seal chain shows seal Vault unsealed and main cluster 3/3 unsealed.
- Seal agent node (`seal-agent`) visible with AppRole + mTLS status text, token TTL and secret-id age.
- Licence expiry is in the future.
- Optional `@failover` test (env flag `ENABLE_FAILOVER_TEST=true`): delete
  the active Vault pod via `oc`; assert leadership moves on the Cluster page
  within 10s; assert 3/3 unsealed resumes.

### `audit.spec.ts`

- `finn`: audit page loads; at least one entry visible; raw JSON expands;
  HMAC'd field marker visible.
- Collector-offline banner absent (collector is running).

### `a11y.spec.ts`

- axe WCAG 2.1 A/AA on every screen for `ada` and `finn`, plus sign-in.
  **0 violations required** at 1440×900 and 390×844.
- Also run with `reducedMotion: 'reduce'` — gear motif must not animate,
  no swing, no pulse; states crossfade.

### `screens.spec.ts` (`@screens`)

- Every screen at 1440×900 and 390×844 → `docs/screenshots/`.
- `make ui-screens` runs this spec.

### Make targets

- `make ui-test` — everything except `@failover` and `@screens`.
- `make ui-test-failover` — the `@failover` test (requires
  `ENABLE_FAILOVER_TEST=true` and `oc` on PATH).
- `make ui-screens` — screenshot spec.

## Validation

`make ui-test` green; `make ui-screens` produces the screenshot set; paste
the summary into the execution log.

Record any deviations: flaky tests, timing adjustments, Mac-sleep edge cases.

## Execution log

Appended by each run: what was done, deviations and why, validation output.
