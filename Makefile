SHELL  := /bin/bash
RUN    := ./scripts/ansible-run.sh
TF     := ./scripts/tf-run.sh
PHASES := ./scripts/phases.txt

.DEFAULT_GOAL := help

.PHONY: help
help: ## List all targets with descriptions
	@awk 'BEGIN{FS=":.*## "} /^[a-zA-Z0-9_-]+:.*## /{printf "  \033[1m%-26s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ── Dependencies ─────────────────────────────────────────────────────────────
.PHONY: deps
deps: ## Install pinned Ansible collections and check required tools
	@./scripts/ansible-deps.sh

# ── OpenShift Local lifecycle ────────────────────────────────────────────────
.PHONY: crc-delete crc-reset crc-up crc-down crc-status crc-console

crc-delete: ## Destroy the CRC VM (keeps cache + pull secret); idempotent
	@./scripts/crc-delete.sh

crc-reset: ## Destroy the CRC VM and create a fresh one from scratch
	@make crc-delete && make crc-up

crc-up: ## Configure + start OpenShift Local (8 vCPU / 24 GB / 80 GB)
	@./scripts/crc-up.sh

crc-down: ## Stop OpenShift Local (keeps the VM and all cluster data)
	@crc stop

crc-status: ## Show CRC status and cluster health
	@crc status

crc-console: ## Print console URL + kubeadmin credentials and open the web console
	@crc console --credentials

# ── Static gate ───────────────────────────────────────────────────────────────
.PHONY: check
check: deps ## Static gate — ShellCheck, tf fmt/validate/test, sg_stats unit tests, substrate grep
	@./scripts/check.sh

# ── Terraform phases ──────────────────────────────────────────────────────────
.PHONY: infra foundation workloads seal platform

infra: ## tf infra — substrate contract root (discovers apps_domain, pod_cidr)
	$(TF) infra apply

foundation: ## tf foundation — namespaces, RBAC, NetworkPolicies, Routes, VSO Subscription
	$(TF) foundation apply

workloads: ## tf workloads — Helm releases, seal-agent, rotator, identity stack, VSO resources
	$(TF) workloads apply

seal: ## tf seal — transit mount + autounseal key, AppRole roles on seal Vault
	$(TF) seal apply

platform: ## tf platform — Vault namespace, mounts, policies, token roles, file audit
	$(TF) platform apply

# ── Ansible phases ─────────────────────────────────────────────────────────────
.PHONY: prepare seal-init agent bootstrap identity configure ux validate unseal

prepare: ## ansible prepare — TLS certs, licence Secrets, CA ConfigMaps; waits for VSO CSV
	$(RUN) prepare

seal-init: ## ansible seal-init — init + unseal seal Vault, bootstrap policies, sg-tf-seal + sg-ansible-seal tokens
	$(RUN) seal-init

agent: ## ansible agent — secret-ids into Secrets, prove agent, rotator credentials
	$(RUN) agent

bootstrap: ## ansible bootstrap — cluster init, raft join, platform bootstrap policies, sg-tf-platform + sg-ansible-platform tokens
	$(RUN) bootstrap

identity: ## ansible identity — LDAP seed, Keycloak realm, Vault OIDC/JWT/LDAP auth
	$(RUN) identity

configure: ## ansible configure — kubernetes/approle/cert auth, DB connection, KV seeds, agent demo, socket audit
	$(RUN) configure

ux: ## ansible ux — UI/API builds, evidence ConfigMap sync
	$(RUN) ux

validate: ## ansible validate — read-only end-to-end proof → .build/validation.json
	$(RUN) validate

unseal: ## Unseal the seal Vault (1 share/threshold 1)
	$(RUN) unseal

# ── Full lab workflow ─────────────────────────────────────────────────────────
.PHONY: lab
lab: ## Run all phases in order, then the three gates; on failure prints exact resume command
	@./scripts/lab.sh

# ── Gates ──────────────────────────────────────────────────────────────────────
.PHONY: idempotency drift secret-scan boundary rotation-proof

idempotency: ## Re-run every Ansible phase; changed=0 required (idempotency-allow.txt for exceptions)
	@./scripts/idempotency.sh

drift: ## Terraform plan -detailed-exitcode on all roots + Ansible --check on all phases
	@./scripts/drift.sh

secret-scan: ## Scan for leaked secrets: known values, hv[sbr] tokens, PEM keys, licence prefix
	@./scripts/secret-scan.sh

boundary: ## Prove tool boundary: 19 sys/capabilities-self checks across all four bootstrap tokens
	@./scripts/boundary-check.sh

rotation-proof: ## Rotate the seal agent AppRole secret-id twice; prove old=400, current=200, count=1
	@./scripts/rotation-proof.sh

# ── Lifecycle ─────────────────────────────────────────────────────────────────
.PHONY: up down reset verify

up: ## Bring the full stack up from a stopped state (idempotent)
	@./scripts/down.sh up

down: ## Scale all workloads down gracefully (never deletes PVCs or .secrets/)
	@./scripts/down.sh down

reset: ## DESTRUCTIVE: delete namespaces + generated state (requires typing 'shift-gear')
	@./scripts/down.sh reset

verify: ## Full stack health: cluster operators, seal chain, Vault HA, licence, VSO, gates
	@./scripts/verify-stack.sh

# ── Layers (console data) ────────────────────────────────────────────────────
.PHONY: layers

layers: ## Emit .build/evidence.json + layers.json (what the console shows) from the running system
	@./scripts/evidence.py

# ── Vault status ─────────────────────────────────────────────────────────────
.PHONY: status vault-roll

status: ## Nodes, cluster operators, seal Vault + cluster Vault status, licence expiry, VSO CSV
	@./scripts/verify-stack.sh

vault-roll: ## Controlled roll for OnDelete: standbys first, leader last; each waits for 3 voters
	@./scripts/vault-roll.sh

# ── Identity ──────────────────────────────────────────────────────────────────
.PHONY: identity-verify identity-show-user

identity-verify: ## Every persona logs in through all auth methods and receives exactly their policies
	$(RUN) identity-verify

identity-show-user: ## Print one person's password from Vault KV (usage: make identity-show-user PERSON=ada)
	@./scripts/identity-show-user.sh $(PERSON)

# ── VSO workloads ─────────────────────────────────────────────────────────────
.PHONY: vso-status wl-a-rotate wl-a-status wl-b-status

vso-status: ## VSO resource sync status and workload pod states
	@./scripts/vso-status.sh

wl-a-rotate: ## Write a new KV version for app-config; VSO syncs within ~30s, workload-a rolls
	@./scripts/wl-a-rotate.sh

wl-a-status: ## Show workload-a pod state and last mounted Secret version
	@KUBECONFIG=.secrets/kube/config oc -n sg-workloads get deploy/workload-a

wl-b-status: ## Show workload-b pod state and last DB credential lease
	@KUBECONFIG=.secrets/kube/config oc -n sg-workloads logs deploy/workload-b --tail=20

# ── UI ────────────────────────────────────────────────────────────────────────
# ── CA trust ──────────────────────────────────────────────────────────────────
.PHONY: trust untrust trust-status

trust: ## Add the lab CA to the macOS System keychain as a trusted root (sudo)
	@./scripts/trust.sh trust

untrust: ## Remove the lab CA from the macOS System keychain (sudo)
	@./scripts/trust.sh untrust

trust-status: ## Is the lab CA trusted? Does macOS accept shiftgear.apps-crc.testing?
	@./scripts/trust.sh status

# ── UI ────────────────────────────────────────────────────────────────────────
.PHONY: ui-test ui-test-failover ui-screens ui-check

ui-test: ## Playwright journeys + axe WCAG 2.1 AA at 1440×900 and 390×844 (passwords read from Vault, never on disk)
	@./scripts/ui-test.sh --grep-invert '@failover|@screens'

ui-test-failover: ## Run the @failover Playwright test (requires ENABLE_FAILOVER_TEST=true)
	@ENABLE_FAILOVER_TEST=true ./scripts/ui-test.sh --grep @failover

ui-screens: ## Screenshot every screen at 1440×900 and 390×844 → docs/screenshots/
	@./scripts/ui-test.sh --grep @screens

ui-check: ## Nuxt type-check + ESLint pass
	@cd ui && npm run typecheck && npm run lint
