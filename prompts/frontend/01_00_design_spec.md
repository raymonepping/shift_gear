# Frontend 01_00 — Shift Gear design spec

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

Every Vault project uses the **Vault daylight glass** system. Before
anything else, load the user-level skill **`vault-ui-design`**
(`~/.claude/skills/vault-ui-design/`: `SKILL.md`, `vault-glass.css`,
`shell.css`) and read the canonical implementations:
- `../red_doors/ui/` — the most recent and complete Vault daylight glass UI.
- `../golden_ticket/ux/` — the UI/UX source to reuse for Shift Gear (the
  latest generation of the red_pass console: shell, components, Layers page,
  BFF session handling, Playwright + axe setup).
- `../red_doors/docs/frontend/DESIGN.md` — the design reference.

This spec adds what is specific to Shift Gear. Where it is silent, the
skill rules. Output of this prompt: `docs/frontend/DESIGN.md` for Shift Gear
plus token additions in `ui/app/assets/css/main.css`. No screens yet
(that is `01_01`).

## The world

Vault daylight glass: pale window-lit ground, aluminium mullions, frosted
panes, black ink. Shift Gear's brand element is **gear motion** — the
impression that machinery is engaged, interlocking, turning. This is
expressed through line-art gear motifs on the hero page and subtle
transition timing (`cubic-bezier(0.16,1,0.3,1)`, not bounce), not through
animation that would distract from real system state.

## Token additions specific to Shift Gear

Extend `vault-glass.css` with a `/* Shift Gear additions */` section:

- `--sg-gear-ink`: `#1f3a5f` (deep indigo — the gear stroke colour on
  the hero; not used for text or status).
- `--sg-layer-tf`: `#eef2f7` (Terraform surface tint — backgrounds of
  Terraform-sourced data cards).
- `--sg-layer-ansible`: `#f0f7ee` (Ansible surface tint — backgrounds of
  Ansible-sourced data cards).
- `--sg-layer-operator`: `#f7f3ee` (Vault Operator surface tint).
- `--sg-layer-agent`: `#f5f0fb` (Vault Agent surface tint).

These tints communicate the **provenance layer** without colour-coding
status. Each panel states its layer in text ("Configured by Ansible",
"Synced by Vault Operator") and uses the tint only as a background wash.
The tints must not be used for text, borders or pills.

## Layer provenance panel

The most important UI concept in Shift Gear: **every piece of displayed
state shows which layer produced it.**

- A small pill or header strip on each card reads: `Terraform` · `Ansible` ·
  `Vault Operator` · `Vault Agent` · `Vault API` as appropriate.
- The layer is not derived by the UI — it is a property of the data returned
  by the API (`/api/v1/state`). The UI never infers or guesses provenance.
- If provenance is unknown the strip reads "unknown — not reported".

## Layout primitives specific to Shift Gear

- **Dashboard** (the hero): a frosted glass pane centred on the page, with
  a line-art gear pair in `--sg-gear-ink` that forms the background of the
  Shift Gear wordmark. Below it: four status tiles (Vault Cluster, Vault
  Operator, Ansible state, Vault Agent), each tinted per their layer.
- **Layer diagram**: a read-only, live diagram showing the four layers
  (Terraform → Ansible → Vault Operator / Vault Agent → Workloads) with
  real state: green check or red cross per layer. Below the cluster status
  nodes visible as in Red Doors' Cluster page. Uses CSS grid + SVG arrows;
  no external diagram library.
- **Operator panel**: a two-column view. Left: VaultStaticSecret and
  VaultDynamicSecret CRD objects with their sync status, last-sync time,
  and rotation controls. Right: workload deployments with mounted Secret
  status. Operator-layer tint.
- **Ansible panel**: a read-only view of the last `ansible-validate` run
  output (stored by the API); each check shown as ✓/✗/⚠ with the raw
  Ansible output collapsible. Ansible-layer tint.
- **Agent panel**: Vault Agent injection status; the injected secret's key
  names (never values); last renewal time; token TTL countdown.
- **Audit**: identical to Red Doors — recent entries, filter by engine/path,
  raw JSON collapsible, HMAC'd fields marked.
- **Cluster**: identical to Red Doors — seal chain, nodes, Raft, licence.
- **Sign-in**: ink hero "Terraform. Ansible. Operator. One system.",
  one sign-in button.

## Layout primitives specific to Shift Gear

The golden_ticket `ux/` (observed live) is the canonical reference for
layout and navigation. The following primitives are directly derived from it,
adapted from MultiPass VMs to OpenShift pods:

- **Fleet** (the main dashboard): dark ink hero with eyebrow, headline, and
  five stat tiles (Pods, Vault Secured, Raft Voters, Reachable, Compute).
  Below the tiles: the inline seal chain diagram (seal Vault → seal agent →
  vault-0/1/2). Below that: Pods and Operator summary tiles.
- **Layers**: dark hero + **Gates** row (four cards: Idempotency · Drift ·
  Secret scan · Validation, each showing the script name and pass/fail pill)
  + **Phases** table from `.build/layers.json` (interleaved Terraform/Ansible
  rows, each with a status pill). Terraform rows: blue pill; Ansible rows:
  muted pill — matching the tool tints.
- **Engines**: dark hero + **Mounted engines** responsive card grid (Live
  pill, Enterprise badge, mount path, plugin version) + **"Not mounted, on
  purpose"** table sourced from Terraform output.
- **Pods**: dark hero + per-pod cards in a grid. Each card has four indicator
  cells (2×2): Provisioned (TF), OpenShift health, Ansible (Converged), and
  Vault/Service status. Role badges: SEAL VAULT · CLUSTER · SEAL AGENT ·
  IDENTITY · OPERATOR · API · UI.
- **Operator panel**: two-column view — VSO CRD cards (left) + workload
  deployment status (right). Operator-layer tint.
- **Ansible panel**: convergence digest comparison + validate results.
  Ansible-layer tint.
- **Agent panel**: Vault Agent injection status, TTL countdown, key names.
  Agent-layer tint.
- **Audit**: recent entries, filter by engine/path, HMAC'd fields marked.
- **Cluster**: full seal chain detail, Raft peers, licence expiry.
- **Sign-in**: ink hero, one sign-in button.

## Pages (designed here, built in 01_01)

Fleet, Layers, Engines, Routes, Pods, Operator, Ansible, Agent, Audit,
Cluster, Sign-in.

Sidebar groups:
- *Fleet*
- *Layers*
- *Engines*
- *Routes*
- *Pods*
- *Platform* (Operator · Ansible · Agent)
- *Governance* (Audit)
- *Cluster*

Topbar: **Seal chain pill** (always visible, e.g. `● Seal chain 3/3`) ·
signed-in user · role badge · Sign out.

Footer tagline (all pages): *"Terraform builds the house. Ansible decorates it.
Vault keeps the keys."* Footer links: **Build · Decorate · Seal · Prove**.

## Deliverables

- `docs/frontend/DESIGN.md` (Shift Gear), stating it follows `vault-ui-design`
  and documenting the layer tokens, the provenance panel convention, and the
  gear motif rule.
- Token additions in `ui/app/assets/css/main.css`.
- A static component sheet page (`/_design`, dev-only) showing the layer
  provenance panel in all four flavours and the gear motif at the dashboard
  scale, for sign-off before `01_01`.

## UI/UX code reuse

Reuse the following from `../golden_ticket/ux/` as the starting point for `ui/`:

- `app/app.vue`, `app/assets/css/` — base styles and shell.
- `app/components/` — all components that are not golden_ticket-specific
  (shell, topbar, layers, gate cards, checks drawer, footer).
- `app/composables/` — all composables.
- `app/middleware/` — auth middleware.
- `server/` — BFF session handling, OIDC flow, proxy.
- `playwright.config.ts`, `tests/` — test setup.

Do not reuse golden_ticket pages or page-specific components directly; adapt them
to the Shift Gear page structure above.

## Validation

Screenshot `/_design` at 1440×900 and 390×844; axe scan 0 violations;
reduced-motion screenshot shows no gear animation. Present the sheet to
the user for sign-off before `01_01`.

## Execution log

Appended by each run: what was done, deviations and why, validation output.
