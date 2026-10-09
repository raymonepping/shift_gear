# Frontend design spec — Shift Gear

This document governs all UI work in `ui/`. It follows the **Vault daylight glass** design
system (`main.css` — the same system used in `golden_ticket/ux/`, `red_doors/ui/`, and the
Arcanium / Editors Factory family). The rules here extend and specialise that system for the
Shift Gear context; where silent, the `vault-ui-design` skill applies.

---

## Design world

**Vault daylight glass:** pale window-lit ground, aluminium mullions, frosted panes, black ink.
The hero band is the page's one dark ink pane. Everything else is glass on a pale canvas.

**Shift Gear brand element:** gear motion — the impression that machinery is engaged,
interlocking, turning. Expressed through line-art gear motifs on the hero dashboard and subtle
`cubic-bezier(0.16,1,0.3,1)` transitions. Not through continuous animation or any motion that
would compete with real system state.

---

## Colour tokens (Shift Gear additions)

Added in `ui/app/assets/css/main.css` under `/* Shift Gear additions */`:

| Token | Value | Use |
|---|---|---|
| `--sg-gear-ink` | `#1f3a5f` | Gear stroke colour on hero only; never text, status, or pill |
| `--sg-layer-tf` | `#eef2f7` | Background tint on Terraform-sourced data cards |
| `--sg-layer-ansible` | `#f0f7ee` | Background tint on Ansible-sourced data cards |
| `--sg-layer-operator` | `#f7f3ee` | Background tint on Vault Operator sourced data cards |
| `--sg-layer-agent` | `#f5f0fb` | Background tint on Vault Agent sourced data cards |

These tints communicate **provenance layer** — not status. Use as `background` only.
Never for text, borders, or pills. Always pair with a text label ("Synced by Vault Operator").

---

## Layer provenance convention

Every data card or panel must show which layer produced the data it displays:

- A small pill or header strip reads: `Terraform` · `Ansible` · `Vault Operator` · `Vault Agent` · `Vault API`
- The layer property comes from the API response (`/api/v1/state` or per-endpoint). The UI
  never infers or guesses provenance.
- If provenance is unknown: the strip reads **"unknown — not reported"**

---

## Gear motif rule

- The line-art gear pair appears **only** on the Fleet (dashboard) hero background.
- It uses `--sg-gear-ink` at `opacity: 0.06` over the dark hero.
- It is pure CSS SVG: `url("data:image/svg+xml,...")` as a `background-image`.
- `@media (prefers-reduced-motion: reduce)`: gear is static. No rotation, no pulse.
- It is never used as a status indicator, a button icon, or a navigation element.

---

## Layout primitives

All derived from `golden_ticket/ux/` and adapted from Multipass VMs to OpenShift pods.

### Fleet (main dashboard)
Dark ink hero with eyebrow, headline, and five stat tiles:
`Pods · Vault Secured · Raft Voters · Reachable · Compute`

Below tiles: inline seal chain diagram (seal Vault → seal agent → vault-0/1/2).
Below diagram: two summary tiles (Pods → Pods page; Operator → Operator page).

### Layers
Dark hero + **Gates** row (4 cards: Idempotency · Drift · Secret scan · Validation, each with
script name and pass/fail pill) + **Phases** table from `.build/layers.json` (interleaved
Terraform/Ansible rows, each with status pill).
Terraform rows: indigo pill. Ansible rows: muted slate pill.

### Engines
Dark hero + **Mounted engines** card grid (Live pill, Enterprise badge, mount path, plugin
version) + **"Not mounted, on purpose"** table.

### Pods
Dark hero + per-pod cards in a responsive grid.
Each card: role badge · 4 indicator cells (2×2): Provisioned (TF) · OpenShift health · Ansible · Vault/Service.

Role badges: `SEAL VAULT` · `CLUSTER · LEADER` · `CLUSTER` · `SEAL AGENT` · `IDENTITY` · `OPERATOR` · `API` · `UI`

### Routes
Dark hero + route rows. Each row: name · clickable URL · TLS termination badge
(`Passthrough` · `Edge` · `Re-encrypt`) · backend pills.

### Operator panel
Two-column: VSO CRD cards (left) + workload deployment status (right).
Background: `--sg-layer-operator`.
Rotate button visible to operators only.

### Ansible panel
Convergence status + validate results.
Background: `--sg-layer-ansible`.
Observe-only note: "Ansible runs on the operator's machine, never from the console."

### Agent panel
Seal agent card + agent-demo sidecar card.
Background: `--sg-layer-agent`.
Key names visible; values never shown.

### Audit
Recent entries table; filter by mount path; raw JSON collapsible;
HMAC'd fields labelled "HMAC — Vault never logs the value".

### Cluster
Full seal chain diagram (matches Fleet inline but with detail).
Leader/standby nodes · Raft peers · agent token TTL · secret-id age · VSO CSV status ·
licence expiry. Refreshes every 5 s.

### Sign-in
Ink hero: "Vault Enterprise on OpenShift — provisioned, converged, sealed by design."
One button: "Sign in with Vault via Keycloak."

---

## Navigation (sidebar)

```
Fleet          ← main dashboard
Layers         ← phases + gates
Engines        ← mounted engines + skipped table
Pods           ← per-pod cards
Routes         ← OpenShift Routes
Operator       ← VSO CRDs panel
Ansible        ← convergence + validate
Agent          ← sidecar injection
Audit          ← Vault audit log
Cluster        ← seal chain + Raft + licence
```

Topbar (persistent, floating glass):
- Left: project name.
- Centre: **Seal chain pill** — `● Seal chain 3/3` (green / amber / red).
- Right: signed-in user · role badge (ADMIN / ENGINEER / AUDITOR / VIEWER) · Sign out.

⌘K palette to jump to any page by name.

---

## Footer (`ShiftGearFooter.vue`)

- Thin aluminium rule with a blue glint (tokens only).
- Tagline (italic, centred, muted): *"Terraform builds the house. Ansible decorates it. Vault keeps the keys."*
- Footer links (small, muted): **Build · Decorate · Seal · Prove** → Layers · Ansible · Cluster · Validate
- Folded "Layer key" (localStorage-remembered): Terraform (indigo) · Ansible (green) · Vault Operator (amber) · Vault Agent (violet)
- `© <year> Raymon Epping` with `.sig-name` clearing sweep (reduced-motion safe)
- Social: GitHub `raymonepping` · X `doctor_nosql` · LinkedIn `raymonepping` · Medium `@raymonepping`

---

## Honesty rules

- Every number and status comes from the API. The UI never invents state.
- Timers count down from TTLs Vault returned. They show "expired" — they do not fake state changes.
- Missing data renders as "not reported", never as a placeholder value.
- A failing layer shows its actual error from the API, not a generic message.

---

## Component sheet (`/_design`, dev-only)

Available at `/_design` when `NUXT_PUBLIC_DESIGN_SHEET=true`. Shows:
- Four layer provenance panels (Terraform · Ansible · Vault Operator · Vault Agent)
- Gear motif at dashboard scale
- Status pills and tone variants
- Footer preview

Used for sign-off before production builds. Not accessible in production (`designSheet: false`).
