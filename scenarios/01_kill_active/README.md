# Scenario 01 — Kill the active Vault pod

**Purpose**: Prove that a Vault standby promotes and the killed pod rejoins the cluster unsealed.

## 3-line presenter script

```bash
bash scenarios/01_kill_active/run.sh
# The script queries each pod's Vault status, deletes the actual leader,
# requires a different leader, then waits for the deleted pod to rejoin.
```

## How to run

```bash
bash scenarios/01_kill_active/run.sh
```

## Expected output

```
==> Scenario 01: killing active pod vault-0
 ok New leader elected: vault-1
 ok Scenario 01 PASS: active pod killed, standby took over, pod rejoined unsealed
```

## Why this works

The Vault cluster uses Raft consensus with three voters. Killing one pod leaves
two voters, which is still a quorum. The pod restarts and auto-unseals through
the seal agent over mTLS without operator action. No Shamir key is needed and
no token is exposed.
