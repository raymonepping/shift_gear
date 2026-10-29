# addons/rotation/consumer/consumer.mk — the Secure Door consumer (prompts 01_09, 01_10).
# Included by addons/rotation/rotation.mk.

CONSUMER := ./addons/rotation/consumer/scripts/consumer.sh

.PHONY: rotation-consumer-up rotation-consumer-down rotation-consumer-status rotation-consumer-logs rotation-consumer-test

rotation-consumer-up: ## KV rotation add-on — Secure Door verifier + client + board: install and prove [GRACE=30|0 for strict]
	@GRACE=$(GRACE) $(CONSUMER) up

rotation-consumer-down: ## KV rotation add-on — remove the Secure Door consumer only (secret, history and controller stay)
	@$(CONSUMER) down

rotation-consumer-status: ## KV rotation add-on — Secure Door: both parties' versions, key ring, verdicts, denial windows, latency
	@$(CONSUMER) status

rotation-consumer-logs: ## KV rotation add-on — follow a Secure Door log [P=client|verifier|board] [C=agent|probe] [F=0]
	@P=$(P) C=$(C) F=$(F) $(CONSUMER) logs

rotation-consumer-test: ## KV rotation add-on — live proof of the Secure Door consumer (d01–d07 + leak check) [S=nn]
	@$(CONSUMER) test $(if $(S),--only $(S),)
