# Changelog

All notable changes to Shift Gear are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- KV v2 value rotation add-on (`addons/rotation/`, ADR D17). Install it with `make rotation-up` and remove it with `make rotation-down`; every managed secret and its history stay in Vault. See [docs/rotation.md](docs/rotation.md).
- Per-type rotation policies (generator, schedule, `max_age`, `min_length`, `max_reads`) in `addons/rotation/rotation.yaml`, validated by Terraform, `make rotation-validate` and the controller.
- Time-, usage- (Vault audit stream) and event-based rotation: human requests, which Vault authorises, and Vault event notifications with a durable version checkpoint.
- Enforcement by reconciliation and Vault ACL, and compliance reporting (`make rotation-report`, also correct while the controller is down).
- Engines › Rotation in the console: version timeline with fingerprints, compliance, and Rotate now when Vault allows it.
- Secure Door consumer and board (`make rotation-consumer-*`): a Vault Agent–fed app that hot-reloads rotated KV v2 values without restarting, with a fictional door and a Vault daylight glass board at `secure-door.<apps_domain>`. See [addons/rotation/consumer/README.md](addons/rotation/consumer/README.md).
- `make rotation-test`: 11 live scenarios plus a leak check. `make rotation-validate` runs in CI. Scenario 10 shows the demo rotation.

- Live seal-chain observation shared by the topbar and Fleet/Cluster diagrams: bounded TLS-verified member health, named Agent readiness, 15-second foreground polling, 30-second expiry and fail-closed status; no telemetry dependency or additional Vault credential. See [validation](docs/seal-chain-observation.md).

- C02/C03 local acceptance: 43/43 live steps, 148/148 standard browser tests, dedicated failover and all nine scenarios; repository telemetry defaults remain disabled.
- C02 optional OpenTelemetry (preferred) / Prometheus scraping and independently optional bounded, projected audit metadata retention with independent authenticated UI source states and access/redaction/restart proof tooling. Local storage does not establish external custody or M06 recovery.
- C03 isolated Vault Agent database file consumer, separate JWT/policy/connection/table scope and actual lease/isolation/restart proof tooling; [acceptance status](docs/c02-c03-progress.md) records validation.

- C04 read-only policy/ownership explorer with published declaration hashes, local filters and contextual runbooks; no additional runtime privileges. Locally accepted with 41/41 live steps and 138/138 standard browser tests.

- Source-bound local acceptance for S01/S02/S05/S06: 41 live steps, 130 browser tests, failover and all nine scenarios; M06 isolated restore remains deferred.
- Bounded, TLS-verified runtime observation with a dedicated GET-only identity for four named Kubernetes resources; independent source state, freshness and transport reasons.
- Dedicated PKI/Transit issuance, revocation, expiry, rotation and rewrap proofs; live observer RBAC and destructive-plan guard checks.
- Deliverable provider lockfiles, readonly initialization, immutable deployed/build image inputs, explicit OLM approval and private pre-upgrade snapshots with scoped download-only identities.
- Stateless collector Node 22→24 upgrade, configuration rollback/audit recovery and re-upgrade rehearsal, plus current/historical image inventory.
- Investigation guide and source links, shared request feedback/retry, audit path filtering/pagination/restart marker and reactive session-expiry notices.

- Versioned console evidence with observation age, source availability, schema validation and cluster/run identity checks; responsive layouts down to 195 CSS pixels.
- Safe KV rotation receipts, compare-and-set writes, preserved unrelated fields and direct authorization tests across all five personas.
- Validated provider backchannel logout, bounded sessions, mutation-origin checks and a bounded metadata-only audit collector.
- Target-specific automation locks, source-bound run records, independent evidence publication/retry, credential diagnostics and protected live-proof/release workflows.
- Credential expiry/replacement and same-root certificate renewal drills; explicit Terraform/Ansible field ownership and task-level idempotency rules.
- PRD, MoSCoW roadmap, ownership/session/credential runbooks and expanded article draft `article/06.md`.

### Fixed

- Expired bootstrap tokens whose lookup returned HTTP 200: TTL/renewability now determine replacement, with old accessors retired after replacements are persisted.
- OpenShift-owned registry references on the observer ServiceAccount, bounded to the declared controller-owned fields.
- Partial/reordered release receipts: execution and verification now share the complete ordered ladder and relative scenario paths.

- Repeated Keycloak client changes caused by an empty logout-redirect attribute, and Keycloak root routing to the application's `/signin` page.
- Browser TLS verification, stale-snapshot failover assertions and reuse of browser sessions invalidated by provider logout.
- Scenario 08 drift detection/restoration and scenario 01 completion before public HA/Raft recovery.
- Long-lived reviewer JWT in current Terraform state, Agent token exposure through the application's shared volume, and expired SecretID repair/revocation.
- CRC control commands modifying project kubeconfig, nested cold-start lock handoff, hypervisor exit with its controller and chrony configuration errors.

### Verification

- Local live proof on 2026-10-15 passed all 36 steps, including 18 static checks, 33 offline regressions, 120 browser tests, separate failover, screenshots, all nine scenarios, three labs and three full drift checks.
- M06 isolated recovery remains owner-deferred. Protected GitHub release execution is still required; the uncommitted local proof is not a release receipt. See `docs/must-progress.md`.

---

## [1.0.0] — 2025-07-01

### Added — Prompt 01: OpenShift Local cluster, contract root, repo spine

- `scripts/crc-up.sh`, `crc-down.sh`, `crc-delete.sh`, `crc-post-start.sh` — substrate lifecycle scripts
- `scripts/common.sh`, `phases.sh`, `phases.txt` — shared shell library and phase list (13 phases)
- `scripts/lab.sh` — full 13-phase orchestrator with resume-on-failure
- `scripts/check.sh` — static gate: ShellCheck, terraform fmt/validate, substrate grep, ansible-lint
- `scripts/ansible-deps.sh`, `ansible-run.sh`, `ansible-env.sh` — Ansible runner
- `scripts/tf-run.sh` — Terraform wrapper (unsets VAULT_NAMESPACE, sets VAULT_CACERT)
- `terraform/infra/` — substrate contract root: discovers apps_domain, pod_cidr, ingress_ca_path
- `terraform/foundation/` — namespaces, RBAC, NetworkPolicies, Routes, VSO Subscription
- `ansible/ansible.cfg`, `requirements.yml`, `inventory/`, `group_vars/` — Ansible scaffold
- `Makefile` — all targets

### Added — Prompt 02: Seal chain

- `scripts/tls.sh` — project CA + leaf cert generation (notBefore -1h, serverAuth+clientAuth EKU)
- `scripts/boundary-check.sh` — 19 sys/capabilities-self checks
- `policies/seal/autounseal.hcl`, `seal-rotator.hcl`
- `policies/bootstrap/sg-tf-seal.hcl`, `sg-ansible-seal.hcl`
- `deploy/vault-seal/values.yaml`, `deploy/vault/values.yaml`, `deploy/seal-agent/agent.hcl`
- `terraform/workloads/` — Helm releases, seal-agent Deployment, rotator CronJob
- `terraform/seal/` — transit mount, autounseal key, AppRole roles
- `ansible/roles/sg_prepare/`, `sg_seal_init/`, `sg_seal_agent/`, `sg_bootstrap/`

### Added — Prompt 03: terraform/platform, tool boundary, static gate

- `policies/bootstrap/sg-tf-platform.hcl`, `sg-ansible-platform.hcl`
- `policies/platform/sg-engineer.hcl`, `sg-operator.hcl`, `sg-approver.hcl`, `sg-auditor.hcl`, `sg-vso.hcl`, `sg-api.hcl`, `sg-agent-demo.hcl`
- `terraform/platform/` — Vault namespace shift-gear, mounts, policies, token roles, audit
- `scripts/secret-scan.sh` — scan for leaked tokens/keys/licence in tracked files

### Added — Prompt 04: Identity stack

- `deploy/identity/openldap/Dockerfile`, `entrypoint.sh`, `slapd.conf.tmpl`
- `terraform/foundation/main.tf` additions: Keycloak Route, OpenLDAP ImageStream + BuildConfig
- `terraform/workloads/main.tf` additions: NetworkPolicies, OpenLDAP + Keycloak + PostgreSQL Deployments
- `ansible/roles/sg_identity/` — LDAP seed (k8s_exec), Keycloak realm + federation + OIDC client, Vault auth methods
- `ansible/roles/sg_identity_verify/` — per-persona JWT + LDAP login, lookup-self, policy assertion
- `ansible/identity.yml`, `ansible/identity-verify.yml`
- `scripts/identity-show-user.sh`

### Added — Prompt 05: VSO Operator

- `terraform/foundation/main.tf` additions: vso-workloads SA, vault-token-reviewer SA + CRB + token Secret
- `terraform/workloads/main.tf` additions: VaultConnection, VaultAuth, VaultStaticSecret, VaultDynamicSecret, workload-a, workload-b
- `ansible/roles/sg_configure/tasks/secrets.yml`, `k8s_auth.yml`, `database.yml`, `kv_seed.yml`
- `scripts/vso-status.sh`, `scripts/wl-a-rotate.sh`

### Added — Prompt 06: Ansible configure complete + validate

- `ansible/roles/sg_configure/tasks/approle.yml` — AppRole + sg-automation (CIDR bounds)
- `ansible/roles/sg_configure/tasks/cert_auth.yml` — cert auth + internal-client
- `ansible/roles/sg_configure/tasks/k8s_roles.yml` — sg-api + sg-agent-demo k8s roles
- `ansible/roles/sg_configure/tasks/agent_demo.yml` — KV seed for agent demo
- `terraform/workloads/main.tf` additions: agent-demo Deployment (Vault Agent init + sidecar)
- `ansible/roles/sg_validate/` — full validation: health, HA, mounts, policies, seal, routes, VSO, identity
- `ansible/validate.yml`, `ansible/ux.yml`, `ansible/configure.yml`

### Added — Prompt 07: Resilience, gates, lifecycle

- `scripts/down.sh` — down/up/reset lifecycle
- `scripts/crc-down.sh` — substrate script: `crc stop`
- `scripts/vault-roll.sh` — controlled rolling restart (standbys first, leader last)
- `scripts/rotation-proof.sh` — two rotations; proves old=400/current=200/count=1
- `scripts/verify-stack.sh` — ✓/⚠/✗ rows for all stack components
- `scripts/layers.sh` — emits `.build/layers.json`
- `scripts/idempotency.sh`, `drift.sh`, `automation-digest.sh`
- `scenarios/01_kill_active/` through `scenarios/08_drift_detection/` — 8 resilience scenarios
- `Makefile` — verify, layers, all lifecycle targets

### Added — Docs 01: Documentation

- `README.md` — project thesis, prerequisites, quick start, phase list, all URLs, targets
- `docs/getting-started.md` — first run walkthrough, expected timings, first sign-in
- `docs/architecture.md` — namespaces, seal chain, HA topology, ownership table, VSO flow, mermaid diagram
- `docs/substrate-contract.md` — thesis, cluster output, isolation rule, worked example, what is proven
- `docs/layers.md` — per-phase inputs, outputs, idempotency, resume
- `docs/security-model.md` — secret boundary, Terraform state analysis, token hygiene, demo vs. production
- `docs/operations.md` — all make targets, rebuild timings, cold start, rotation, renewal, proof tables
- `docs/demo-guide.md` — 10-min and 5-min run sheets
- `docs/testing.md` — all gates and how to run them
- `docs/decisions.md` — D01–D14 with evidence
- `docs/lessons-learned.md` — L01–L21 from the full series
- `docs/troubleshooting.md` — symptom → cause → fix for all known issues
- `docs/enterprise.md` — lab→enterprise mapping table
- `CHANGELOG.md` — this file

### Added — Docs 02: Article 05

- `article/05.md` — "Keep the Dream Alive": Vault Enterprise on OpenShift, the fifth lab
- `article/STYLE.md` — series style guide (copied from golden_ticket)
