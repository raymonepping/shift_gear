# addons/rotation/consumer/consumer.mk — the Secure Door consumer (prompt 01_09).
# Included by addons/rotation/rotation.mk.

CONSUMER := ./addons/rotation/consumer/scripts/consumer.sh

.PHONY: rotation-consumer-up rotation-consumer-down rotation-consumer-status rotation-consumer-logs rotation-consumer-test

rotation-consumer-up: ## KV rotation add-on — Secure Door consumer + board: install and prove (Agent → hot reload → fictional door)
	@$(CONSUMER) up

rotation-consumer-down: ## KV rotation add-on — remove the Secure Door consumer only (secret, history and controller stay)
	@$(CONSUMER) down

rotation-consumer-status: ## KV rotation add-on — Secure Door: credential, refresh, connectivity, door verdict, latency, board URL
	@$(CONSUMER) status

rotation-consumer-logs: ## KV rotation add-on — follow the Secure Door console [C=agent|probe|board] [F=0]
	@$(CONSUMER) logs

rotation-consumer-test: ## KV rotation add-on — live proof of the Secure Door consumer (c01–c07 + leak check) [S=nn]
	@$(CONSUMER) test $(if $(S),--only $(S),)
