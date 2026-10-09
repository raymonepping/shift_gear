---
version: 1
slug: "ui-app-app-vue"
primary_target: "ui/app/app.vue"
related_targets: ["ui/app/pages"]
---

# Durin Web Console — surface brief

Scope: the whole authenticated Web Console (all routes under ui/app/pages) plus the sign-in page.
Mode: Operate (presenter-led demo; the presenter operates, the audience reads over their shoulder).

Audience/job: a presenter tells the Protect → Recover → Compromise → Shield → Isolation → Break Glass story to security architects and CISOs, switching personas (raymon, barend, viewer, security-admin). Success: the audience can point at any value and say who may clear it.

Constraints: API contract docs/api/API_CONTRACTS.md; tokens never in the browser (BFF); every verdict is Vault's real answer; own identity, no HashiCorp colours; glassmorphism pinned by the user; professional.

## Direction contract

THESIS: Protected data is switchable privacy glass. A value stays frosted — its ciphertext blurred behind the pane — until Vault authorises the signed-in person; then that pane, and only that pane, clears. Refuses the category default of KPI cards plus tables with glass as a panel effect: here the frost IS the encryption state.

OWN-WORLD: daylight office glazing. Pale mineral ground (#e9eef3) behind thin brushed-aluminium mullions; frosted panes (white 55%, blur 18px, white hairline highlight, soft offset shadow); graphite ink #0f1a2a; cleared state teal #0d9488 with a frame LED; ciphertext violet #6d28d9 in JetBrains Mono; authority azure #0369a1; break glass amber #b45309; denied #dc2626; tenant glass tints azure / jade / rose. Hanken Grotesk for everything else. Lucide icons, 1.5 stroke.

STORY: the audience sees frosted values everywhere, watches one clear when the operator acts, watches it refuse to clear for viewer, sees stolen copies stay frosted forever after Shield, and sees break glass clear exactly once after an approval in Vault.

FIRST VIEWPORT: Overview at 1440×900: left, a frosted aluminium-framed rail (logo, scenario rail with a moving "now" light, sections). Top, a thin frame bar: tenant switcher, Vault LED pill (leader), person + role + key-tag TTL bar drawn to scale. Main: a glass wall of three tenant panes side by side, each showing protected values frosted with their key versions etched below and a live authority strip; primary action "Start the story → Protect" sits bottom-right of the wall.

FORM: Smart Privacy Glass (PDLC switchable glass) — my own list position 1, taken as IMPECCABLE’S PICK over the roll; seed key 2f17203d. Signature interaction: "The Clearing" — on Vault ALLOWED a pane's backdrop blur wipes to clear top-to-bottom in 520ms and its frame LED turns teal; on DENIED it stays frosted, the LED turns red and Vault's verdict is etched on the glass. Motion grammar: 180ms state transitions, one clearing moment per result, reduced-motion = instant.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

Raises kept from declined challengers: scenario rail with a moving "now" light; every scenario step deep-linkable; one glass tint per tenant everywhere; TTLs and control-group windows drawn as bars to exact scale.
