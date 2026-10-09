# Docs 02 — Article 05: The substrate is not the architecture

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

All prompts 01–11 are done. `make lab` converges clean from nothing. Every
gate passes. The article series in `../golden_ticket/article/`
(`01.md`–`04.md`) closes the multi_pass → red_pass → golden_ticket arc.
Shift Gear is the continuation: the same Vault architecture, the same
Terraform + Ansible discipline, moved onto OpenShift.

**Deal with the promise honestly.** Article 04 ends with *"This is the last
one."* The opening must own that in a sentence or two (for example: it was
the last build on Multipass; the architecture wanted to know whether it
survives a different substrate). Do not pretend 04 left the door open.

Read before writing:

- `../golden_ticket/article/01.md` — multi_pass: three VMs, Terraform wrapping
  Ansible, *contracts win*.
- `../golden_ticket/article/02.md` — red_pass: Ansible alone, eight VMs,
  *evidence wins*.
- `../golden_ticket/article/03.md` — the rule for which job belongs to which
  tool, *a Vault platform needs both answers*.
- `../golden_ticket/article/04.md` — golden_ticket: Terraform + Ansible rebuilt
  on lessons learned, the boundary enforced by Vault.
- `../golden_ticket/article/STYLE.md` — the style rules that govern the whole
  series. Follow them exactly.
- `docs/architecture.md`, `docs/substrate-contract.md`, `docs/layers.md`,
  `docs/operations.md`, `docs/security-model.md` in this repository — every
  number the article quotes must trace to one of these files or to a command
  run against the running system.

## Goal

Write `article/05.md`, the fifth article in the series on Medium.
It adds no code. It tells the Shift Gear build as the one the first four
were pointing toward — the moment when the substrate finally disappeared.

| Article | Lab | Shape | Closing line |
| --- | --- | --- | --- |
| `01.md` | `multi_pass` | Terraform wrapping Ansible: three VMs, a baton | *Contracts win.* |
| `02.md` | `red_pass` | Ansible only: eight VMs, a seal chain, people, a console | *Evidence wins.* |
| `03.md` | both, compared | which job belongs to which tool | *A Vault platform needs both answers.* |
| `04.md` | `golden_ticket` | Terraform + Ansible, built on the lessons; the boundary enforced by Vault | *Vault keeps the keys.* (and: *This is the last one.*) |
| `05.md` | `shift_gear` | Vault on OpenShift: same architecture, new substrate, the contract tested for real | *Keep the dream alive.* |

### The frame: Oasis, "Keep the Dream Alive" (2005)

The song is on *Don't Believe the Truth* (2005). Verify the year and the
line against the official lyrics page
(`https://www.oasisinet.com/lyrics/keep-the-dream-alive/`) before quoting.
Quote **one short line at most** (e.g. the title line), credited to Oasis;
everything else from the song is paraphrased or simply implied.

The series has been a dream project: a Vault Enterprise platform, fully
automated, running on a single Mac. Four labs. Each one closer to how a real
enterprise runs Vault. Each one a collision between an architectural ideal and
the practical limits of a laptop.

The dream was never the VMs. The dream was a Vault architecture that is
substrate-independent — the same playbooks, the same CRDs, the same policies,
regardless of whether the cluster underneath is a Multipass VM, an OpenShift
Local instance, or a production OCP cluster. Shift Gear is where the dream
stopped being theoretical.

Use the song as the emotional arc, not as a quotation engine. Quote one
short line once, in the opening, credited to Oasis, *Keep the Dream Alive*
(2005). Do not work lyrics into the technical sections. Let the idea carry
the structure:

- *"no stranger to this place"* — the tools and patterns are the same as
  the four labs before.
- *"where real life and dreams collide"* — OpenShift on a Mac: the
  production substrate, running as a laptop lab.
- *"even though I fall from grace"* — the surprises: clock drift cascades,
  CSV gates, EKU requirements, the things that go wrong.
- *"keep the dream alive"* — the substrate contract holds. The architecture
  survives the substrate change.

The closing line of this article, and the series: *Keep the dream alive.*

## Voice and rules

- Follow `../golden_ticket/article/STYLE.md` exactly: first person singular
  for the author's own work; inclusive "we" only where it draws the reader into
  a shared question.
- Run the `no-ai-slop` editorial pass before calling it final; re-check every
  "we", "our" and "us".
- Match the series: short paragraphs, single-line punches used sparingly, real
  code from this repository (not invented), tables where they compare. Target
  **3,000–3,800 words**.
- Never print secrets, tokens, role-ids, licence data or RHSM values.
  Route hostnames (e.g. `vault.apps-crc.testing`) are fine.
- Every number and claim must come from this repository or from the runs in
  prompts 01–11 (`.build/layers.json`, `.build/convergence.json`,
  `.build/gates/<gate>.json`, `docs/`, `CHANGELOG.md`, `git log --oneline`).
  Note: gate results are in individual files under `.build/gates/` (e.g.
  `.build/gates/idempotency.json`, `.build/gates/drift.json`) — not a single
  `.build/gates.json`. Measure; do not estimate. If a number cannot be
  measured, leave it out.
- The Commodores' *Three Times a Lady* (Lionel Richie, 1978) belongs to
  article `04.md`. Do not use it here. The Oasis frame is this article's own.
- **Lyric rule**: one short line, once, in the opening, credited to Oasis
  (*Keep the Dream Alive*, 2005). No other lyric text anywhere; the ideas
  above may shape the sections without being quoted.

## Structure

1. **Title and subtitle.**
   Title: *Keep the Dream Alive*
   Subtitle: *Vault Enterprise on OpenShift — the fifth lab, and the one
   where the substrate finally disappeared.*

2. **Opening.** The song: one line, credited. The promise from article 04,
   owned honestly. Then: this
   is a lab project that started on a Mac with three Multipass VMs and ended
   on the same Mac running OpenShift Local — a production-grade container
   platform on a laptop. The dream that kept the series going was not a
   bigger cluster. It was an architecture that does not know what it runs on.
   Shift Gear is where that stopped being a claim and became a grep command
   with zero matches.

3. **What did not change.** One section. The ownership rule (Terraform
   builds the house, Ansible decorates it). The seal chain (seal Vault →
   seal agent with AppRole and mTLS → cluster nodes holding no token). The
   phase list interleaving both tools (`infra`, `foundation`, `prepare`,
   `workloads`, `seal-init`, `seal`, `agent`, `bootstrap`, `platform`,
   `identity`, `configure`, `ux`, `validate`). The gates. The
   Vault Operator pattern (VaultConnection → VaultAuth → VaultStaticSecret /
   VaultDynamicSecret → workload pods with no Vault token). The token boundary
   (the four bootstrap tokens). The *patterns* did not change; their
   implementation did (Helm instead of systemd, NetworkPolicies instead of
   firewalld, a CronJob instead of a timer).

4. **The substrate contract.** The central architectural idea. Quote the
   `cluster` output block from `terraform/infra/outputs.tf` (verbatim, six
   fields; say which are discovered from the cluster). Explain each field in one line. Show the isolation check command
   (`grep -rnE 'crc|vfkit|apps-crc' terraform/foundation terraform/workloads terraform/seal terraform/platform ansible` — expected:
   zero matches). This is not a new idea — golden_ticket's `lab_nodes` output
   is the same concept for VMs. Shift Gear extends it to a cluster API.
   **Be exact about what is proven**: the contract has one implementation
   (CRC). The grep proves nothing above infra knows CRC; it does not prove
   the lab runs on ROSA. Say so.

5. **What OpenShift changed.** Not the architecture — the substrate layer.
   Three things that required real work:
   - **No VMs to address directly**: Ansible no longer SSH's to nodes;
     it connects to the Vault API through a Route. The inventory is a set
     of Vault addresses and OpenShift API URLs, not a list of IP addresses.
   - **The Vault Secrets Operator**: `VaultStaticSecret` and
     `VaultDynamicSecret` CRDs remove Vault credentials from workload pods
     entirely. This is not possible in the VM-based labs; it is native to
     OpenShift.
   - **In-cluster builds**: the UX is containerised (multi-stage Dockerfile,
     BuildConfig + ImageStream). The evidence files (`.build/*.json`)
     reach the API pod as a ConfigMap synced by Ansible — a pod cannot read
     the Mac's disk.
   Show the `make lab` phase list from `.build/layers.json` (same interleaved
   Terraform/Ansible structure as golden_ticket, more seams — and why each
   seam exists).

6. **The Vault Operator is the third layer.** Golden_ticket has two tools:
   Terraform and Ansible. Shift Gear has three: Terraform provisions, Ansible
   configures, the Vault Operator *operates* — syncing secrets into workload
   pods at runtime without any credential in the pod. Walk through one
   `VaultStaticSecret` from CRD definition to the Secret object in the workload
   namespace. Show the rotation moment: one `make wl-a-rotate` command; VSO
   syncs within 30 seconds; the workload rolls; the UI shows the new value's
   age. No token. No script. No Ansible task.

7. **The token boundary on OpenShift.** Golden_ticket article 04 introduced
   the concept. Shift Gear keeps the same four bootstrap tokens
   (`sg-tf-seal`, `sg-ansible-seal`, `sg-tf-platform`,
   `sg-ansible-platform`): Terraform can build structure but cannot mint a
   secret-id, enable an auth method or delete `kv/`; Ansible can configure
   people and mint secret-ids but cannot create a mount or write a policy.
   The Vault Secrets Operator uses Kubernetes auth
   — not a token at all; the pod's projected SA token is the credential.
   Workloads: no credential. The boundary is wider than two tools now.
   Show `make boundary`'s check table (output only — no token values).

8. **The receipt.** Measured with commands, shown as a table comparing the
   full series:

   | | `multi_pass` | `red_pass` | `golden_ticket` | `shift_gear` |
   | --- | --- | --- | --- | --- |
   | Substrate | Multipass VMs | Multipass VMs | Multipass VMs | OpenShift (CRC) |
   | Terraform roots | 3 | 0 | 3 | 5 |
   | Phases in `make lab` | (measure) | 9 | 11 + 3 gates | (measure) |
   | Vault servers | 3 | 4 (3 + seal) | 4 (3 + seal) | 4 (3 + seal) |
   | Seal credential on the cluster | — (Shamir) | none (seal agent) | none (seal agent) | none (seal agent) |
   | Application secret delivery | — | — | — | VSO: no credential in the pod |
   | Swapping the substrate | rewrite infra | rewrite three Multipass roles | a new `terraform/infra` (contract written down, never built) | a new `terraform/infra` (contract with one implementation, isolation proven by grep) |

   Fill every "(measure)" with a command's output; verify every other cell
   against the repositories before publishing (the golden_ticket values come
   from its `docs/` and article 04). The last row is the point of the
   article — and it is honest about what has and has not been proven.

9. **Drift, both kinds — on OpenShift.** The same two kinds of drift
   from golden_ticket article 04 exist here. Terraform drift: a Helm value
   changed with `oc edit`, a mount disabled by hand. Ansible drift: a
   Keycloak client changed in the admin API, a person added to another LDAP
   group. (Note: Terraform does not see objects it never declared — a stray
   ConfigMap is invisible to it; say so if it comes up.) One table showing
   which tool sees which change, from `docs/operations.md`.
   Add the third kind unique to OpenShift: **VSO sync drift** — a `Secret`
   whose content no longer matches the Vault path it came from. `make verify`
   catches it via `VaultStaticSecret.status.lastSyncTime`.

10. **The console learned the substrate.** The Fleet page shows what Terraform's
    `workloads` root owns (pods, compute totals), checked against the
    OpenShift API. The Layers page shows the same interleaved Terraform/Ansible phases
    as golden_ticket, plus the four gates. The Routes page (the OpenShift
    equivalent of golden_ticket's Front door) shows every Route with its TLS
    termination mode and live backend health — no HAProxy required.
    One paragraph per page. No screenshots in the article (Medium renders them
    poorly at this length); reference them in the repository's
    `docs/screenshots/` instead.

11. **From nothing to converged.** The full-rebuild timings per phase from
    the final from-nothing `make lab` (`docs/operations.md`), and what a
    second `make lab` does: every `terraform plan` exits 0, every Ansible phase reports
    `changed=0`. Total time for first run vs second run. These numbers come
    from `docs/operations.md` (prompt 07 and the final clean gate in
    docs/01).

    For reference and comparison: the predecessor lab (golden_ticket) ran
    from nothing to fully converged in **17 minutes 12 seconds** on the same
    Mac, with per-phase breakdown: infra 6m05s, converge 58s, seal-init 23s,
    seal (TF) 2s, agent 24s, bootstrap 35s, platform (TF) 2s, proxy 23s,
    identity 2m20s, ux 1m, validate 57s, gates 4m. Shift Gear's equivalent
    timing is in `docs/operations.md`. Quote both in the article for
    context; the reader can then judge the OpenShift substrate cost directly.

12. **Surprises.** Three or four from `docs/lessons-learned.md` that
    actually happened in this build (the execution logs decide; the
    candidates below are only candidates):
    - The `notBefore = -1h` lesson (TLS certs issued at T=0 rejected by a
      node whose clock shows T-30s after a Mac sleep).
    - The `serverAuth + clientAuth` requirement: the Vault pods present
      their certificate as a client to the seal agent's mTLS listener.
    - The VSO CSV gate: never apply a `VaultConnection` before the CSV
      reaches `Succeeded` — the error message is not obvious.
    - The clock drift cascade: Mac sleep → CRC VM clock jump → projected SA
      tokens look expired → Vault Kubernetes auth returns 403 → chrony
      hardening (`makestep 1.0 -1`, `maxpoll 6`) resolves it.
    Short. One or two sentences each. No invented numbers.

13. **What the series taught, all five together.** Five principles, one per
    lab:
    - `multi_pass`: *contracts win* — a stable output contract lets tools
      compose without coupling.
    - `red_pass`: *evidence wins* — nothing is green until something checked
      it; a badge without a drawer is a lie.
    - the comparison (`03.md`): *a platform needs both answers* — lifecycle
      questions are Terraform's; order-and-moment questions are Ansible's.
    - `golden_ticket`: *the boundary is a policy, not a convention* — Vault
      enforces what each tool can do; a cultural rule is not enough.
    - `shift_gear`: *the substrate is not the architecture* — the Vault
      platform, the Ansible playbooks and the VSO resources only know the
      contract; on another OpenShift cluster only `terraform/infra/` would
      change (one implementation so far — say so).
    One paragraph on what this means at enterprise scale: HCP Terraform
    workspaces per substrate, AAP for Ansible, dynamic credentials via the
    Vault Operator. No sales tone. Cite `docs/enterprise.md` in this
    repository — the file maps every lab mechanism to its enterprise
    counterpart, following the same lab→enterprise table structure as
    `golden_ticket/docs/enterprise.md`. If the file does not yet exist,
    `docs/01_write_documentation.md` creates it; this article references it
    once it does.

14. **Close.** One line: the grep command with zero matches. Then the
    question the series leaves open: what does this look like on a real
    cluster — vSphere, ROSA, bare-metal OCP? The `terraform/infra/` module
    is the only answer needed.

    End with the song's final phrase — no quotation marks, no attribution,
    no fanfare. Just the idea, in plain prose: *the dream is alive.*

    Then the repository links for all five labs:
    - `shift_gear`: `https://github.com/raymonepping/shift_gear`
    - `golden_ticket`: `https://github.com/raymonepping/golden_ticket`
    - `red_pass`: `https://github.com/raymonepping/red_pass`
    - `multi_pass`: `https://github.com/raymonepping/multi_pass`

## Also

- `README.md`: add an "Articles" section linking the full series (01–05),
  with the Medium URL for each once published.
- `CHANGELOG.md`: entry for this prompt.
- `article/STYLE.md`: copy from `../golden_ticket/article/STYLE.md` into
  `article/STYLE.md` in this repository, so the series style travels with
  the lab.

## Done when

- `article/05.md` exists; every number in it traces to a command or a file
  in this repository (keep the measurement commands in your final report,
  not in the article).
- STYLE.md pass and no-ai-slop pass done; no authorial "we"; no marketing
  language; every claim is measurable.
- The Oasis lyric appears exactly once, in the opening, in full, with
  correct attribution and the URL. Nowhere else.
- The closing phrase *"the dream is alive"* (or equivalent plain prose
  paraphrase) appears in the final paragraph only.
- `make secret-scan` still clean; `git status` shows only the article,
  README, CHANGELOG, and STYLE.md changes.
- Commit: `git commit -m "docs: article 05, keep the dream alive"`.

## Execution log

Appended by each run: what was done, deviations and why, validation output.
