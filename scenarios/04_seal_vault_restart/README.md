# Scenario 04 — Seal Vault restarts

**Purpose**: Prove the seal Vault restarts sealed (Shamir 1/1 — no auto-unseal), the main cluster keeps serving during the outage, and `make unseal` fully restores the seal chain.

## 3-line presenter script

```bash
oc -n sg-vault-seal delete pod -l app.kubernetes.io/instance=vault-seal --grace-period=0
curl -sk https://vault.<apps_domain>/v1/sys/health | jq .sealed   # still false
make unseal && curl -sk https://vault-seal.<apps_domain>/v1/sys/health | jq .sealed  # false
```

## How to run

```bash
bash scenarios/04_seal_vault_restart/run.sh
```

## Expected output

```
==> Scenario 04: restarting seal Vault pod
 ok Cluster still serving (HTTP 200)
 ok Seal Vault is sealed after restart (expected) — running make unseal
 ok Scenario 04 PASS: seal Vault restarted sealed, cluster kept serving, make unseal restored chain
```

## Why this works

The seal Vault uses Shamir 1/1 and has no auto-unseal of its own — it must be manually unsealed with the single key stored in `.secrets/seal-init.json`.  The main Vault cluster's transit seal wrapping key is cached in memory; it can serve requests and unseal new pods as long as the seal agent is running.  The seal Vault only needs to be reachable for new pod starts and secret-id rotation.
