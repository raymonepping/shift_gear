# addons/rotation/rotation.mk — KV v2 value rotation add-on (ADR D17).
# Included by the core Makefile with `-include addons/rotation/rotation.mk`.
# Not to be confused with `rotation-proof` (the seal agent secret-id rotator).

ROTATION := ./addons/rotation/scripts/rotation.sh

# ── KV rotation add-on ──────────────────────────────────────────────────────
.PHONY: rotation-up rotation-down rotation-status rotation-history rotation-rotate \
        rotation-read rotation-report rotation-logs rotation-plan rotation-restart \
        rotation-validate rotation-test

rotation-up: ## KV rotation add-on — install (Terraform + Ansible) and prove it rotates
	@$(ROTATION) up

rotation-down: ## KV rotation add-on — remove; every secret, version and history record stays in Vault
	@$(ROTATION) down

rotation-status: ## KV rotation add-on — controller state + every managed secret (version, fingerprint, compliance)
	@$(ROTATION) status

rotation-history: ## KV rotation add-on — version history of SECRET=<type>/<name> (REVEAL=1 prints values)
	@$(ROTATION) history

rotation-rotate: ## KV rotation add-on — request a rotation of SECRET=<type>/<name> [REASON=…] (event trigger)
	@$(ROTATION) rotate

rotation-read: ## KV rotation add-on — read SECRET once (usage-based demo; prints the fingerprint only)
	@$(ROTATION) read

rotation-report: ## KV rotation add-on — compliance report (works while the controller is down)
	@$(ROTATION) report

rotation-logs: ## KV rotation add-on — controller logs [C=agent|events] [F=1]
	@$(ROTATION) logs

rotation-plan: ## KV rotation add-on — Terraform plan + Vault configuration in check mode
	@$(ROTATION) plan

rotation-restart: ## KV rotation add-on — restart the controller pod (never touches Vault)
	@$(ROTATION) restart

rotation-validate: ## KV rotation add-on — offline gate: unit tests, config, terraform, ansible-lint, shellcheck
	@$(ROTATION) validate

rotation-test: ## KV rotation add-on — live proof of every strategy, enforcement and compliance [S=nn]
	@$(ROTATION) test $(if $(S),--only $(S),)

# The Secure Door consumer (prompt 01_09) has its own targets.
-include addons/rotation/consumer/consumer.mk
