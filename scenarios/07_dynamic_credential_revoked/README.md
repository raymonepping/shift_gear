# Scenario 07 — Dynamic credential revoked

**Purpose**: Prove the VSO dynamic secret path: revoke the active DB lease → VSO detects the revocation → mints a new credential → old PostgreSQL user is dropped.

## 3-line presenter script

```bash
# Revoke workload-b's lease directly
LEASE=$(oc -n sg-workloads get secret db-creds -o jsonpath='{.metadata.annotations.secrets\.hashicorp\.com/vaultDynamicSecretLease}')
vault lease revoke -namespace=shift-gear "$LEASE"
make wl-b-status   # new username in log within ~30 s
```

## How to run

```bash
bash scenarios/07_dynamic_credential_revoked/run.sh
```

## Expected output

```
==> Scenario 07: current db user = v-kube-vso-worklo-XXXX
 ok Lease revoked
 ok New credential minted: v-kube-vso-worklo-YYYY
 ok Old user 'v-kube-vso-worklo-XXXX' gone from pg_roles ✓
 ok Scenario 07 PASS: lease revoked, new credential issued, old user removed
```

## Why this works

`VaultDynamicSecret` with `renewalPercent=67` renews the lease at 67 % of its TTL (5 m × 0.67 ≈ 3.3 m).  When the lease is revoked externally, VSO's reconcile loop detects the 403/404 on the next renewal attempt and immediately re-reads `creds/demo-reader` to obtain a fresh username/password.  Vault's revocation statement (`pg_terminate_backend` + `DROP ROLE`) runs as part of the revocation, removing the old user from PostgreSQL.
