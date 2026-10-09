# Scenario 01 — Kill the active Vault pod

**Purpose**: Prove that a Vault standby promotes to leader within seconds and the killed pod rejoins the cluster unsealed.

## 3-line presenter script

```bash
oc -n sg-vault delete pod $(oc -n sg-vault get pods -l app.kubernetes.io/name=vault -o name | head -1 | sed 's|pod/||') --grace-period=0
# watch a standby become active (< 10 s)
oc -n sg-vault get pods -l app.kubernetes.io/name=vault -w
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

The Vault cluster uses Raft consensus with 3 voters.  Killing one pod leaves 2 voters — still a quorum — so a standby is elected within one Raft heartbeat timeout (typically < 10 s).  The pod restarts and auto-unseals through the seal agent (transit seal mTLS) without any operator action.  No Shamir key is needed and no token is exposed.
