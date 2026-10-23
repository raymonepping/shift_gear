# Scenario 07 — Dynamic credential revoked

**Purpose**: Prove the VSO dynamic secret path: revoke the active DB lease → VSO detects the revocation → mints a new credential → old PostgreSQL user is dropped.

## 3-line presenter script

```bash
# Revoke workload-b's lease directly
LEASE=$(oc -n sg-workloads get vaultdynamicsecret db-creds -o jsonpath='{.status.secretLease.id}')
vault lease revoke -namespace=shift-gear "$LEASE"
make wl-b-status   # inspect the replacement username after reconciliation
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

`VaultDynamicSecret` with `renewalPercent=67` renews the lease at 67 % of its TTL (5 m × 0.67 ≈ 3.3 m).  When the lease is revoked externally, VSO's reconcile loop detects the failed lease renewal on the next renewal attempt and immediately re-reads `creds/demo-reader` to obtain a fresh username/password.  Vault's revocation statement (`pg_terminate_backend` + `DROP ROLE`) runs as part of the revocation, removing the old user from PostgreSQL.

The proof allows 240 seconds for the next scheduled renewal, rather than
assuming an immediate notification when a lease is revoked. It must revoke
the actual lease; deleting the Secret is not a substitute.

The bootstrap policy allows only the demo-reader lease path. It rejects a
body `lease_id` because the [Vault API](https://developer.hashicorp.com/vault/api-docs/system/leases#revoke-lease)
lets that parameter override the path. Generic and prefix revocation remain
denied.
