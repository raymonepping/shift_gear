# Scenario 02 — Restart the seal agent

**Purpose**: Prove the cluster continues serving while the seal agent restarts and that the agent re-authenticates (new AppRole token) without operator intervention.

## 3-line presenter script

```bash
oc -n sg-vault-seal delete pod -l app.kubernetes.io/name=seal-agent --grace-period=0
oc -n sg-vault-seal get pods -w           # watch agent pod restart
curl -sk https://vault.<apps_domain>/v1/sys/health | jq .sealed   # still false
```

## How to run

```bash
bash scenarios/02_restart_seal_agent/run.sh
```

## Expected output

```
==> Scenario 02: deleting seal-agent pod to force restart
 ok Cluster serving during agent restart (HTTP 200)
 ok Seal agent back Available
 ok Scenario 02 PASS: seal agent restarted, cluster kept serving, agent re-authenticated
```

## Why this works

The main Vault cluster stores the transit-seal wrapping key internally — it does not need to contact the seal agent for every request.  The seal agent is only called when a pod restarts (to unseal it).  The running cluster pods remain sealed-state-false throughout.  When the agent pod restarts it re-authenticates to the seal Vault via AppRole auto-auth and presents a fresh transit-encrypt token.
