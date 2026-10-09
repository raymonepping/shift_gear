#!/usr/bin/env bash
# scenarios/07_dynamic_credential_revoked/run.sh — Revoke workload-b's lease.
# Expected: VSO fetches a new credential; the old user disappears from pg_roles.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../scripts/common.sh"
require_kubeconfig
require_cmd oc jq

INFRA="${BUILD_DIR}/terraform/infra.json"
APPS_DOMAIN="$(jq -r '.cluster.apps_domain' "${INFRA}")"
VAULT_ADDR="https://vault.${APPS_DOMAIN}"
VAULT_CA="${SECRETS_DIR}/tls/pub/ca.pem"
TOKEN_FILE="${SECRETS_DIR}/tokens/ansible-platform"
VAULT_TOKEN="$(cat "${TOKEN_FILE}")"

# Read the current db username from the db-creds Secret
old_user=$(oc -n sg-workloads get secret db-creds \
  -o jsonpath='{.data.username}' 2>/dev/null | base64 -d || echo "")
[[ -n "${old_user}" ]] || die "db-creds Secret not found or username empty"
info "Scenario 07: current db user = ${old_user}"

# Get the lease ID from the VSO annotation
lease_id=$(oc -n sg-workloads get secret db-creds \
  -o jsonpath='{.metadata.annotations.secrets\.hashicorp\.com/vaultDynamicSecretLease}' \
  2>/dev/null || echo "")
if [[ -n "${lease_id}" ]]; then
  info "  revoking lease ${lease_id}"
  curl -sf --cacert "${VAULT_CA}" \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H "X-Vault-Namespace: shift-gear" \
    -X PUT \
    -d "{\"lease_id\":\"${lease_id}\"}" \
    "${VAULT_ADDR}/v1/sys/leases/revoke" >/dev/null
  ok "Lease revoked"
else
  info "  no lease annotation found — forcing VSO re-mint by deleting Secret"
  oc -n sg-workloads delete secret db-creds --ignore-not-found
fi

# Wait for VSO to issue a new credential (renewalPercent=67 triggers before expiry)
info "  waiting for VSO to mint a new credential"
deadline=$(($(date +%s) + 60))
new_user=""
while [[ $(date +%s) -lt ${deadline} ]]; do
  new_user=$(oc -n sg-workloads get secret db-creds \
    -o jsonpath='{.data.username}' 2>/dev/null | base64 -d || echo "")
  [[ -n "${new_user}" && "${new_user}" != "${old_user}" ]] && break
  sleep 3
done

if [[ -n "${new_user}" && "${new_user}" != "${old_user}" ]]; then
  ok "New credential minted: ${new_user}"
else
  die "VSO did not mint a new credential within 60 s (old=${old_user}, current=${new_user:-none})"
fi

# Verify old user no longer exists in postgres
pg_pod=$(oc -n sg-workloads get pod -l app.kubernetes.io/name=postgres \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
[[ -n "${pg_pod}" ]] || die "postgres pod not found"
# Revocation runs Vault's revocation statement; give it up to 30 s.
old_exists=1
for _ in $(seq 1 10); do
  old_exists=$(oc -n sg-workloads exec "${pg_pod}" -- \
    psql -U postgres -tAc "SELECT COUNT(*) FROM pg_roles WHERE rolname='${old_user}'" 2>/dev/null || echo "1")
  [[ "${old_exists}" == "0" ]] && break
  sleep 3
done
[[ "${old_exists}" == "0" ]] || die "Old user '${old_user}' still in pg_roles 30 s after revocation"
ok "Old user '${old_user}' gone from pg_roles"

ok "Scenario 07 PASS: lease revoked, new credential issued, old user removed"
