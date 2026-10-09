# Frontend 01_01 — Shift Gear UI + BFF (Nuxt 4)

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

`01_00` is signed off (design spec + component sheet approved). Prompts
01–07 are done: `make lab` is green through `validate` and the gates. This
prompt builds the **Express API** (starting from `../red_doors/api/`) and
the **UI**, and delivers the `ansible ux` phase. Follow `vault-ui-design`
and Shift Gear's `docs/frontend/DESIGN.md`.

Reuse:
- `../golden_ticket/ux/` — **primary source** for `ui/`. Start from this
  codebase, not from scratch: shell, composables, Layers page, ownership
  from Terraform, gates, checks, footer, Playwright + axe setup.
- `../red_pass/ux/` — the earlier version of the same codebase; background
  only.
- `../red_doors/ui/server/` — BFF session handling and OIDC callback
  (Durin's model, refined in Red Doors; use as reference for OIDC BFF patterns).
- `../red_doors/ui/app/components/` — `AuditDrawer`, `IdentityChips`,
  `OutcomePill`, `DecisionPanel` (adapt, do not re-implement).

Do not copy Red Pass pages or Red Doors door-specific components. Shift
Gear's page structure is distinct.

## Architecture

- **Nuxt 4, `ssr: false` (SPA) + Nitro server as BFF** (Red Doors model;
  hydration mismatches and CSP issues are avoided).
- **Sign-in = Vault OIDC.** `/auth/login` → BFF calls Vault
  `auth/oidc/oidc/auth_url` (role `visitor`,
  `redirect_uri=https://shiftgear.{{ sg_apps_domain }}/auth/callback`) → browser
  → Keycloak → `/auth/callback` → BFF calls `auth/oidc/oidc/callback` →
  **Vault token** + entity + groups. Mention on the sign-in page in one
  sentence: "Your identity is verified by Vault via Keycloak."
- Session server-side (Nitro storage), httpOnly + Secure + SameSite=Lax
  cookie. Session holds: user's Vault token, entity id, display name, groups.
  **Nothing secret reaches the browser.** Sign-out revokes the Vault token.
- BFF → API over the cluster network only (`/api/v1/*` proxy that injects
  `X-Triggered-By` and, for operator panel actions, `X-Vault-Token` from
  the session).
- Route `shiftgear.{{ sg_apps_domain }}` (edge TLS — lesson 19: read from the
  cluster contract, never hardcode `apps-crc.testing`).
- **Containerised in-cluster build** (from golden_ticket, replacing the VM
  service model of red_pass):
  - `ui/Dockerfile` is a **multi-stage build**: stage 1 (`node:lts-alpine`)
    installs deps and runs `nuxt build`; stage 2 (`node:lts-alpine` slim)
    copies only `.output/` and runs `node .output/server/index.mjs`.
  - `deploy/app/ui-buildconfig.yaml`: `BuildConfig` of type `Docker` pointing
    to the `ui/` directory; `output.to` is `ImageStream shift-gear-ui:latest`
    in `sg-app`.
  - `make ui-build`: runs `COPYFILE_DISABLE=1 tar ... | oc start-build
    shift-gear-ui --from-archive=-` — passes the source archive to the
    in-cluster build; no local Docker daemon required.
  - The API and UI **Deployments are Terraform's** (`terraform/workloads`,
    image from the ImageStream via the `image.openshift.io/triggers`
    annotation, `lifecycle { ignore_changes }` on the container image so the
    trigger does not show as drift). The images are built by the
    `ansible ux` phase (below).
  - Lessons applied: `xattr -rc ui/` before archiving; `._*` in
    `.dockerignore`; `node -e "fetch('http://localhost:3000/api/health')"` as
    the `livenessProbe` command.
  - **Evidence files served via API, not disk**: `ansible ux` syncs the
    non-secret `.build/*.json` files (convergence, validation, layers,
    gates, Terraform outputs, identity-verify) into ConfigMap `sg-evidence`
    in `sg-app` **after the secret scan passed**; the API pod mounts it
    read-only. The UI's BFF calls `GET /api/v1/*`; the API serves from the
    mount. A pod cannot read files on the Mac.

## API endpoint summary (for the BFF proxy)

The Express API (`/api/v1`) exposes:

| Endpoint | Purpose |
| --- | --- |
| `GET /fleet` | full fleet state: Vault pod count, sealed/unsealed count, Raft voters, reachable pods, compute totals — all sourced from live evidence (Terraform `workloads` outputs, `make validate`, the OpenShift API) |
| `GET /layers` | phases list (from `.build/layers.json`), gates (idempotency · drift · secret-scan · validation), automation digest, last-run timestamps |
| `GET /engines` | mounted engines (live `sys/mounts` call with a list-only token), not-mounted-on-purpose table (from the `terraform/platform` `engines` output), last-checked timestamp |
| `GET /routes` | OpenShift Routes in all shift-gear namespaces: name, URL, TLS termination mode, backend pod names + roles + Ready status (from `oc get endpoints`); sourced live from the OpenShift API, never cached more than 10s |
| `GET /pods` | per-pod cards: name, role badge, IP/hostname, four indicators (Provisioned, OS health, Ansible converge, Vault/Service status) sourced from their respective evidence files |
| `GET /cluster` | seal chain diagram data: seal Vault → seal agent (AppRole, mTLS) → vault-0/1/2; Raft peers; agent token TTL, secret-id age, last rotator Job; VSO status; licence expiry |
| `GET /operator/static-secrets` | VaultStaticSecret CRDs + Secret sync status |
| `GET /operator/dynamic-secrets` | VaultDynamicSecret CRDs + last lease info |
| `POST /operator/static-secrets/:name/rotate` | trigger secret rotation (operator policy required) |
| `GET /ansible/validate` | last validate output from `.build/validation.json`; never re-runs Ansible |
| `GET /ansible/convergence` | stamp from `.build/convergence.json` + current computed digest + `layers` from `.build/layers.json` |
| `GET /agent/status` | agent pod health, last injection time, token TTL |
| `GET /agent/demo` | injected secret key names (never values) |
| `GET /audit` | recent audit entries; filter by mount path |
| `GET /health` | own health + Vault reachability + collector state |

## Navigation

Sidebar groups (mirroring the golden_ticket `ux/` navigation model seen live):

```
Fleet          ← top-level dashboard (the "provisioned, converged, sealed" hero)
Layers         ← phases table + gates
Engines        ← mounted engines + not-mounted table
Pods           ← per-pod cards (OpenShift equivalent of golden_ticket's "Virtual machines")
Routes         ← OpenShift Routes (equivalent of golden_ticket's "Front door" HAProxy view)
Operator       ← VaultStaticSecret / VaultDynamicSecret panel
Ansible        ← convergence status + validate results
Agent          ← sidecar injection status
Audit          ← Vault audit log
Cluster        ← seal chain + Raft + licence
```

Topbar (persistent, floating glass):
- Left: project logo / name.
- Centre: **Seal chain pill** — e.g. `● Seal chain 3/3` (green when all
  cluster nodes are unsealed via the agent; amber when < 3; red when 0).
  This is the single most important live indicator — it is always visible.
- Right: signed-in user, role badge (ADMIN / ENGINEER / AUDITOR), Sign out.

⌘K palette to jump to any page by name.

## Screens

### 1. Sign-in

Ink hero: **"Vault Enterprise on OpenShift — provisioned, converged, sealed by design."**
One sign-in button ("Sign in with Vault via Keycloak").
`make demo-users` names shown as a presenter hint in dev only.
Build provenance: container image digest + build timestamp in the footer
(injected at build time via `--build-arg BUILD_DIGEST`).

### 2. Fleet (the main dashboard)

Hero panel (dark, ink background):
- Eyebrow: `VAULT ENTERPRISE · OPENSHIFT · TERRAFORM + ANSIBLE`
- Headline: **"Provisioned, converged, sealed by design"**
- Subtext: *"Terraform builds the house. Ansible decorates it. The Vault
  Secrets Operator delivers secrets to workloads. No Vault pod holds a seal
  token."*
- Observe-only notice: *"This console runs inside `sg-app` — lifecycle actions
  run from the host console."*
- Observed timestamp + Refresh button (top-right of hero).

Five stat tiles below the hero (sourced from live evidence — never invented):

| Tile | Label | Value source |
| --- | --- | --- |
| Pods | `SHIFT GEAR PODS` | Terraform `workloads` outputs + the OpenShift API |
| Vault secured | `VAULT SECURED` | node and cluster evidence (`make validate`) |
| Raft voters | `RAFT VOTERS` | `vault operator raft list-peers` |
| Reachable | `REACHABLE` | probe answering count |
| Compute | `COMPUTE` | CPU + memory total across pods |

Below the stat tiles: the **Seal chain diagram** (inline, not a separate page):
```
sg-vault-seal (Shamir 1/1 · Unsealed · Transit key serving)
        ↓
seal-agent (Vault Agent · AppRole token held · mTLS proxy serving)
        ↓  ↓  ↓
vault-0 (Auto-unsealed via the seal agent)
vault-1 (Auto-unsealed via the seal agent)
vault-2 (Auto-unsealed via the seal agent)
```
Each node in the diagram is live; status text is pulled from `GET /fleet`.
Clicking any node navigates to the Cluster page.

Two summary tiles at the bottom of the Fleet page:
- **Pods** tile: `N shift-gear pods · N reachable · all green` — links to Pods page.
- **Operator** tile: `N VaultStaticSecrets synced · N VaultDynamicSecrets active` — links to Operator page.

### 3. Layers

Hero panel:
- Eyebrow: `SCRIPTS/PHASES.TXT · ONE PHASE LIST, TWO TOOLS`
- Headline: **"Terraform builds it · Ansible decorates it"**
- Subtext: *"Every phase of `make lab` in order, with the evidence each tool
  leaves behind, and the gates that must be green before the system counts
  as converged."*
- Summary line (green when all pass):
  `N Terraform · N Ansible phases · every phase and gate green · evidence X min ago`
- Automation digest line:
  `automation unchanged since the last make lab (<digest-short>…)` or
  `automation changed — re-run make lab`

**Gates section** (sourced from `.build/gates/<gate>.json`, one file per
gate, written by the gate scripts at the end of `make lab`):

Four gate cards, each with a `● pass` / `● fail` pill, timestamp, and the
exact script invocation that produced the result:

| Gate | Script | What it checks |
| --- | --- | --- |
| Idempotency | `scripts/idempotency.sh` | every Ansible phase again, `changed=0` |
| Drift | `scripts/drift.sh` | `terraform plan -detailed-exitcode` per root + `ansible --check` |
| Secret scan | `scripts/secret-scan.sh` | known values + secret-shaped patterns |
| Validation | `ansible/validate.yml` | read-only end-to-end proof |

The script name and a one-line description are shown on the card so the
audience can see exactly what "pass" means.

**Phases section** (sourced from `.build/layers.json`):

A numbered table, in the order `make lab` runs them. Each row:
- Number
- Tool badge: `Terraform` (blue pill) or `Ansible` (muted pill)
- Phase name (e.g. `infra`, `prepare`, `seal`, `platform`)
- Summary: `N resources · applied X min ago` (Terraform) or `last run X min ago` (Ansible)
- Status pill: `● plan empty` (Terraform, exit 0) or `● changed=0` (Ansible)

Clicking a phase row expands a detail panel showing the evidence source
(e.g. `.build/layers.json → terraform.infra.resources`) and the last output
summary. Never shows raw Terraform state.

### 4. Engines

Hero panel:
- Eyebrow: `VAULT ENTERPRISE · NAMESPACE ENGINES`
- Headline: **"Secrets engines"**
- Subtext: *"Every engine Vault reports as mounted, read live with a token
  that can list these mounts and nothing else. Display only: Terraform mounts
  them, Vault is the evidence."*
- Summary: `N live · checked HH:MM:SS · from Vault` (green when all
  expected engines are live).

**Mounted engines** section (read live from `sys/mounts` in namespace
`shift-gear` using a minimal list-only token):

Engine cards in a responsive grid. Each card:
- `● Live` status pill.
- `Enterprise` badge if the engine requires an Enterprise licence
  (Key Management, KMIP, SPIFFE, Transform, etc.).
- Engine name (human-readable: "Key/Value", "PKI", "Transit", …).
- Mount path (`kv/`, `pki/`, `transit/`, …).
- One-line description.
- `Type` and `Plugin` version fields (from `sys/mounts` response).

Engines to show for Shift Gear (adapt from golden_ticket's set to the
engines `terraform/platform` mounts):

| Engine | Mount | Enterprise? | Description |
| --- | --- | --- | --- |
| Key/Value | `kv/` | No | Application configuration secrets |
| Transit | `transit/` | No | Encryption as a service |
| PKI | `pki/` | No | X.509 certificates (root CA) |
| PKI Intermediate | `pki-int/` | No | X.509 certificates (intermediate) |
| Database | `database/` | No | Dynamic PostgreSQL credentials |

**"Not mounted, on purpose"** section (sourced from the `terraform/platform`
`engines` output — it lists skipped engines and the reason):

A plain table: engine name · reason skipped. Examples:
- `keymgmt` — needs a cloud KMS provider (not configured in this lab)
- `kmip` — needs an external KMIP listener
- `transform` — Enterprise tokenisation (not enabled in this lab licence tier)

This section makes skipped engines **transparent** — the audience sees exactly
what Terraform decided not to mount and why, instead of wondering whether
something is missing.

### 5. Routes

Hero panel:
- Eyebrow: `OPENSHIFT ROUTER · TLS IN, VERIFIED TLS OUT`
- Headline: **"Routes"**
- Subtext: *"Every OpenShift Route Shift Gear exposes. Passthrough Routes
  hand TLS straight to the pod, so the project CA validates all the way to
  Vault; re-encrypt Routes verify the backend's certificate. Vault writes
  always reach the active node."*
- Summary: `N routes · every route has a healthy backend` (green when all
  backend Services have at least one Ready endpoint).

**Entry points section** (sourced from `oc get route -A -l
app.kubernetes.io/part-of=shift-gear -o json`, live at page load):

Each row:
- Route name (human-readable label, not the k8s name).
- Route URL (clickable `<a>` that opens in a new tab).
- TLS termination badge: `Passthrough` · `Edge` · `Re-encrypt`.
- Backend pills on the right — one per Ready Pod behind the Service
  (pod name + leader/standby role for Vault pods).

Routes for Shift Gear (adapt names to actual Route objects):

| Route name | Namespace | TLS | Backends |
| --- | --- | --- | --- |
| Vault — UI, API, writes (active node) | `sg-vault` | Passthrough | vault-0 leader · vault-1 standby · vault-2 standby |
| Seal Vault (operator) | `sg-vault-seal` | Passthrough | vault-seal-0 |
| Shift Gear console | `sg-app` | Re-encrypt | sg-ui pod |
| Keycloak (realm shift-gear) | `sg-identity` | Re-encrypt | keycloak pod |

Backend health: a backend pill is **green** when the pod is Running + Ready;
**amber** when the pod is Running but not Ready; **red** when the pod is
absent or in Error. The health check uses `oc get endpoints` — never a direct
connection from the BFF.

**"Vault writes always reach the active node"** is enforced by the Passthrough
Route pointing to `vault-active` Service — display which pod currently owns
the `vault-active` Service endpoint.

> Note: golden_ticket uses HAProxy on a dedicated proxy VM (`gt-proxy-1`) to
> achieve the same split (writes to active, reads to any node). Shift Gear
> uses native OpenShift Routes — no HAProxy VM needed. The Routes page is the
> direct functional equivalent, and uses the same visual pattern.

### 6. Pods

Hero panel:
- Eyebrow: `OPENSHIFT · FOUR INDICATORS PER POD`
- Headline: **"Pods"**
- Subtext: *"Every pod Shift Gear manages. Open any indicator to see the
  evidence behind it."*
- Summary: `N shift-gear pods · N reachable · all green`

Pod cards in a grid (one card per pod). Each card:
- Pod name (e.g. `vault-0`, `vault-seal-0`, `seal-agent-…`, `sg-api-…`, `sg-ui-…`)
- Role badge: `SEAL VAULT` · `CLUSTER · LEADER` · `CLUSTER` · `SEAL AGENT` ·
  `IDENTITY` · `OPERATOR` · `API` · `UI`
- Status pill: `● Reachable` / `● Unreachable`
- Namespace and pod IP (from `oc get pod -o wide`).
- **Four indicator cells** (2×2 grid inside the card):

  | Indicator | Label | Source |
  | --- | --- | --- |
  | Provisioned | `PROVISIONED` | Terraform `workloads` outputs (the Deployment/StatefulSet that owns the pod is in Terraform state) |
  | OS health | `OPENSHIFT` | `oc get pod` — `Running` / `Ready` |
  | Ansible | `ANSIBLE` | `.build/convergence.json` — `Converged` or `Outdated` |
  | Vault/Service | `VAULT` / `SERVICE` | `/v1/sys/health` (Vault pods) or `/health` endpoint (service pods) |

- Resource summary: CPU requests · memory requests · PVC size (if stateful).

Clicking any indicator cell expands a panel showing the raw evidence: the
Terraform resource ID, the `oc describe pod` status, the convergence stamp
timestamp, or the Vault health JSON — whichever is appropriate.

### 7. Operator panel

Two columns:
- Left: VaultStaticSecret + VaultDynamicSecret CRD cards. Each card: name,
  Vault path, type (static/dynamic), last sync time, target Secret name,
  workload deployment, **Rotate** button (operators only).
- Right: workload-a and workload-b Deployment status (replicas, restarts),
  last Secret update, mounted Secret key names (never values).
- **Rotation moment**: Rotate → "syncing…" spinner → poll until
  `last_sync_time` changes → show new value's age. Never fakes the update.
- Operator layer tint (`--sg-layer-operator`) throughout.

### 8. Ansible panel

Two sections:
- **Convergence status**: `GET /ansible/convergence`. Stored `automation_digest`
  vs current computed digest, side-by-side. States: `converged` · `outdated` ·
  `never-run` · `unknown`. Ansible layer tint.
- **Validate results**: `GET /ansible/validate` (`.build/validation.json`).
  Each check as ✓/✗/⚠ with task name; raw JSON expandable. Observe-only:
  Ansible runs on the operator's machine, never from the console (the page
  says so in one sentence).

### 9. Agent panel

Two agents, two cards: the **seal agent** (token held, TTL, secret-id age,
last rotator Job) and the **agent demo** sidecar (render timestamp, token
TTL countdown, key names — never values). Agent layer tint. Missing data →
"not reported".

### 10. Audit

Recent Vault audit entries; filter by mount path; raw JSON collapsible;
HMAC'd fields labelled "HMAC — Vault never logs the value"; "collector offline"
banner when socket device is not receiving.

### 11. Cluster

The seal chain as a live diagram (matches Fleet's inline version but with
full detail): seal Vault → seal agent (AppRole token + mTLS) → vault-0/1/2.
Leader/standby, Raft peers, agent token TTL and secret-id age, VSO CSV status, licence expiry
and days remaining. Refreshes every 5s. During the "kill the active pod" demo,
leadership visibly moves.

Shell: frosted rail (sidebar groups as above), topbar with the seal chain
pill, ⌘K palette.

### Signature footer (`ShiftGearFooter.vue`)

Port the footer pattern from `../red_pass/prompts/10_prompt.md` and
`../golden_ticket/ux/` as `ShiftGearFooter.vue`, in-flow at the bottom
of every page (not fixed; also on sign-in). The golden_ticket footer
tagline is the canonical reference:

- A thin aluminium rule with a blue glint (tokens only).
- **Footer tagline** (italic, centred, muted): *"Terraform builds the
  house. Ansible decorates it. Vault keeps the keys."*
- **Footer links** (small, muted, space-separated): **Build · Decorate ·
  Seal · Prove** — each links to the corresponding page (Layers · Ansible ·
  Cluster · Validate). These are navigation shortcuts as much as brand copy.
- A folded **"Layer key"** (localStorage-remembered) naming each layer
  tint once: Terraform (blue), Ansible (green), Vault Operator (amber),
  Vault Agent (violet).
- `© <year> Raymon Epping` with the clearing sweep on hover/focus
  (`.sig-name`, reduced-motion safe).
- Social links (GitHub `raymonepping`, X `doctor_nosql`, LinkedIn
  `raymonepping`, Medium `@raymonepping`) with `aria-label`s and
  `rel="noopener noreferrer"`.

## Honesty rules (identical to Red Doors)

- Every number, identity and status comes from the API; the UI never invents
  state.
- Timers count down from TTLs Vault returned; they show "expired" — they do
  not trigger fake state changes.
- Missing data renders as "not reported", never as a placeholder value.
- A failing layer shows its actual error from the API, not a generic message.

## Deliverables

`api/` (Express, from `../red_doors/api/`), `ui/` (Nuxt 4), the API and UI
Deployments, Services and Route in `terraform/workloads` / `foundation`,
generated API types from `openapi/shift-gear.yaml`.

### `ansible ux` (the last phase before `validate`)

- Build the API and UI images in-cluster (`oc start-build --from-archive`,
  after `xattr -rc` and with `COPYFILE_DISABLE=1`), **only when the source
  digest changed** (store the digest as an annotation on the ImageStream),
  so a re-run is `changed=0`.
- Issue the API's Vault token through Terraform's `sg-ui` token role (with
  `sg-ansible-platform`) into Secret `sg-api-vault` (`no_log`); renew rather
  than re-issue while valid.
- Enable the **socket audit device** to the API collector
  (`sg-api-audit.sg-app.svc:9090`) once the collector is Ready; the file
  device stays as the fallback. Assert, don't re-enable, on later runs.
- Sync `.build/*.json` into ConfigMap `sg-evidence` after the secret scan;
  `scripts/lab.sh` syncs once more after the convergence stamp. This sync is
  the one entry in `scripts/idempotency-allow.txt`.
- `make ux` runs the phase; `make ui-build` / `make api-build` force a
  build.

## Validation

Walk every screen as `ada` (engineer access — all panels readable, no rotate
buttons), as `cleo` (operator — rotate buttons visible and functional), and
as `finn` (auditor — audit page full access, operator panel read-only).

Screenshot every screen at 1440×900 and 390×844 in one batch, fix in one
pass, confirm once. Axe scan must be 0 violations (full suite in `02_01`).

Rotation demo: trigger rotate as `cleo` → watch the Operator panel card
update live → confirm `workload-a` restarted and shows the new Secret age.

## Execution log

Appended by each run: what was done, deviations and why, validation output.
