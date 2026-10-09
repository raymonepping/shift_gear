# Scenario 06 — Static secret rotation

**Purpose**: Prove the VSO static secret path: write a new KV version → VSO detects the change within `refreshAfter=30s` → workload-a rolls automatically.

## 3-line presenter script

```bash
make wl-a-rotate                            # writes rotated_at= to app-config KV
oc -n sg-workloads get pods -w              # watch workload-a pod roll
make wl-a-status                            # confirm new pod is Running
```

## How to run

```bash
bash scenarios/06_static_secret_rotation/run.sh
```

## Expected output

```
==> Scenario 06: workload-a current pod: workload-a-6d5b4f8c9-xvt2p
==>   Writing new app-config version (make wl-a-rotate)
 ok app-config updated — VSO will sync within ~30 s and workload-a will roll
 ok workload-a rolled: workload-a-6d5b4f8c9-xvt2p → workload-a-6d5b4f8c9-kl9mq
 ok Scenario 06 PASS: app-config updated, VSO synced, workload-a rolled
```

## Why this works

`VaultStaticSecret` has `refreshAfter: 30s`.  The VSO controller polls the KV v2 version every 30 s and compares the secret MAC.  When it detects a new version it re-writes the destination Secret and patches the `workload-a` Deployment with a rollout annotation, triggering a pod replacement.  The workload never holds a Vault token or address.
