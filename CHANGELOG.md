# Changelog

All notable changes to Shift Gear are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

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
