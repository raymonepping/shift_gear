# Scenario 05 — Cold start

**Purpose**: Prove the full stack survives `make down && make up` — the cluster auto-unseals through the seal agent and a second `make lab` reports plans empty and Ansible `changed=0`.

## 3-line presenter script

```bash
make down           # scale everything to 0, crc stop
make up             # crc start, scale up, auto-unseal
make lab && make lab   # second run: zero changes
```

## How to run

```bash
bash scenarios/05_cold_start/run.sh
# then manually:
make lab && make lab
```

## Expected output

```
==> Scenario 05: cold start (make down && make up)
 ok Scenario 05 PASS: cold start successful — cluster auto-unsealed, make verify passed
==>   Run 'make lab && make lab' to confirm second run is plans-empty and changed=0
```

## Why this works

`make down` gracefully scales every deployment to 0 replicas — no PVCs or Secrets are deleted, so all persisted state survives.  `make up` starts the seal Vault, calls `make unseal` (one Shamir key), then starts the seal agent.  The main Vault pods start and immediately call the seal agent's transit-unseal endpoint.  All subsequent pods auto-unseal without any further operator action.

> **Note**: if the seal agent's secret-id expired while stopped (> 24 h), `make up` automatically runs `make agent` to re-mint it before starting the agent.
