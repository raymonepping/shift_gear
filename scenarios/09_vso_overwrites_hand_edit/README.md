# Scenario 09 — VSO and a hand-edited Secret

**Purpose**: Find out what the Vault Secrets Operator does when someone edits
a Secret it owns. The scenario edits one key of `sg-workloads/app-config` by
hand and waits for VSO to put the Vault value back.

## 3-line presenter script

```bash
oc -n sg-workloads patch secret app-config --type merge -p '{"data":{"log_level":"aGFuZC1lZGl0ZWQ="}}'
oc -n sg-workloads get secret app-config -o jsonpath='{.data.log_level}' | base64 -d   # watch it change back
oc -n sg-workloads get vaultstaticsecret app-config -o jsonpath='{.status.conditions}'
```

## How to run

```bash
bash scenarios/09_vso_overwrites_hand_edit/run.sh      # TIMEOUT=90 by default
```

## Expected output

Recorded from the first real run (roadmap 03_01).

## Safety

- Never writes to Vault; compares the Secret by a hash of its data and never
  prints a value.
- If VSO does not restore the Secret within the timeout, the script forces a
  resync (an annotation on the `VaultStaticSecret`, as `sg_configure` does),
  confirms the original data is back, and exits non-zero. A failed run leaves
  the lab as it found it.
