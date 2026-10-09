# Shift Gear — Prompt Roadmap

Execute in this order. Each prompt is self-contained, starts by reading
`base_project/00_01_shift_gear.md` (which wins on any conflict), and ends
with an **Execution log** the run appends to (what was done, deviations and
why, validation output). Do not start a prompt before the previous one's
validation passes. After each prompt, `make lab` must be green up to the
last phase that prompt delivers.

| # | Prompt | Delivers | Phases (`scripts/phases.txt`) |
| --- | --- | --- | --- |
| 0 | [base_project/00_01_shift_gear.md](base_project/00_01_shift_gear.md) | Vision, decisions, ownership, the tool boundary, phase list, lessons 1–31, definition of done (read-only) | — |
| 1 | [base_project/01_01_openshift_local_cluster.md](base_project/01_01_openshift_local_cluster.md) | CRC clean slate (`crc-delete`, `crc-reset`), CRC sized + running, the contract root, `foundation` (namespaces first), repo spine, Makefile, `phases.txt`, `tf-run.sh`, `ansible-run.sh`, `sg_stats` callback | `tf infra`, `tf foundation` |
| 2 | [base_project/02_01_vault_seal_and_cluster.md](base_project/02_01_vault_seal_and_cluster.md) | TLS + licence, seal Vault, seal agent + rotator, 3-node Vault auto-unsealed through the agent, VSO subscription, four bootstrap tokens | `ansible prepare`, `tf workloads`, `ansible seal-init`, `tf seal`, `ansible agent`, `ansible bootstrap` |
| 3 | [base_project/03_01_vault_terraform_baseline.md](base_project/03_01_vault_terraform_baseline.md) | `terraform/platform` (namespace, mounts, policies, token roles, audit), `prevent_destroy` + Vault policy (D11), `terraform test` per root, `make boundary` (19 checks), `make check` | `tf platform` |
| 4 | [base_project/04_01_identity_stack.md](base_project/04_01_identity_stack.md) | OpenLDAP + Keycloak deployed by Terraform, configured by Ansible; Vault oidc/jwt/ldap auth + external groups; `identity-verify` | `ansible identity` |
| 5 | [base_project/05_01_vault_operator.md](base_project/05_01_vault_operator.md) | Vault-side config VSO needs (Kubernetes auth role, DB connection, KV seed), VSO resources, demo workloads A (static) + B (dynamic) | `ansible configure` (first part) |
| 6 | [base_project/06_01_ansible_configure.md](base_project/06_01_ansible_configure.md) | Remaining configuration (AppRole, cert auth, agent demo, socket audit), `preamble`, full `validate.yml`, convergence stamp, automation digest | `ansible configure` (complete), `ansible validate` |
| 7 | [base_project/07_01_resilience_and_rehydration.md](base_project/07_01_resilience_and_rehydration.md) | `make lab` with the gates (idempotency, drift, secret scan), `make up`/`down`/`reset`/`verify`, scenarios, chrony hardening, `layers.json`, **full rebuild from nothing** | gates |
| 8 | [frontend/01_00_design_spec.md](frontend/01_00_design_spec.md) | Visual contract on top of `vault-ui-design` (sign-off gate) | — |
| 9 | [frontend/01_01_shift_gear_ui.md](frontend/01_01_shift_gear_ui.md) | Nuxt 4 UI + Nitro BFF + Express API: Fleet, Layers, Engines, Routes, Pods, Operator, Ansible, Agent, Audit, Cluster; in-cluster builds; evidence ConfigMap | `ansible ux` |
| 10 | [frontend/02_01_playwright_journeys.md](frontend/02_01_playwright_journeys.md) | Playwright journeys + axe WCAG 2.1 AA gate | — |
| 11 | [docs/01_write_documentation.md](docs/01_write_documentation.md) | README + full docs set (architecture, substrate-contract, layers, security-model, operations, testing, decisions, lessons-learned) | — |
| 12 | [docs/02_write_article.md](docs/02_write_article.md) | Article 05 for Medium | — |

## Lesson inventory

All lessons are in `00_01_shift_gear.md §5`.

| Lessons | Source | Applied in |
| --- | --- | --- |
| 1–12 | Red Doors | prompts 01–07 |
| 13–18 | Multipass labs, Red Doors execution logs | prompts 01, 02, 05, 06 |
| 19–21 | Golden Ticket (substrate contract, tool boundary, separate roots) | every prompt |
| 22 | Golden Ticket D11 (`prevent_destroy` + Vault policy) | prompts 02, 03 |
| 23–24 | Golden Ticket (TLS `notBefore`, serverAuth + clientAuth) | prompt 02 |
| 25 | Golden Ticket (`secret-scan.sh`) | prompts 01, 07 |
| 26–27 | Golden Ticket D14 + final gate (idempotency vs check mode, rebuild from nothing) | prompts 06, 07 |
| 28–31 | Golden Ticket D9, D10, D12, token-role binding | prompts 03, 04, 06, 09 |

## Design

Every UI decision follows the user-level `vault-ui-design` skill
(Vault daylight glass). UI code starts from `../golden_ticket/ux/`
(primary), with `../red_doors/ui/` and `../red_doors/api/` for the
OpenShift BFF/API shape and `../red_pass/ux/` as background. Containerised:
multi-stage Dockerfile, OpenShift BuildConfig + ImageStream. Evidence
(`.build/*.json`) reaches the API pod as ConfigMap `sg-evidence`, synced by
Ansible after the secret scan.
