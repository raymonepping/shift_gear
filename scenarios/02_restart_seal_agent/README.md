# Scenario 02 — Restart the seal agent

**Purpose**: Prove the cluster continues serving while the seal agent restarts and that the agent re-authenticates (new AppRole token) without operator intervention.

## 3-line presenter script

```bash
oc -n sg-vault-seal delete pod -l app.kubernetes.io/name=seal-agent --grace-period=0
oc -n sg-vault-seal get pods -w           # watch agent pod restart
curl --cacert .secrets/tls/pub/ca.pem https://vault.<apps_domain>/v1/sys/health | jq .sealed   # still false
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

The running Vault cluster does not need the transit seal for every request.
During unseal it contacts the seal Vault through the agent proxy.  The running cluster pods remain sealed-state-false throughout.  When the agent pod restarts it re-authenticates to the seal Vault via AppRole auto-auth and presents a fresh transit-encrypt token.

The script requires a replacement pod UID with Ready=True, so the old
Deployment Available condition cannot make the restart check pass early.
