#!/usr/bin/env bash
# scenarios/04_seal_vault_restart/run.sh — Restart the seal Vault.
# Expected: comes back sealed; cluster keeps serving; make unseal restores chain.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../scripts/common.sh"
require_kubeconfig
require_cmd oc jq

INFRA="${BUILD_DIR}/terraform/infra.json"
APPS_DOMAIN="$(jq -r '.cluster.apps_domain' "${INFRA}")"
VAULT_ADDR="https://vault.${APPS_DOMAIN}"
SEAL_ADDR="https://vault-seal.${APPS_DOMAIN}"
VAULT_CA="${SECRETS_DIR}/tls/pub/ca.pem"

info "Scenario 04: restarting seal Vault pod"
oc -n sg-vault-seal delete pod -l app.kubernetes.io/instance=vault-seal --grace-period=0

# The cluster must keep serving while the seal Vault is down: it is already
# unsealed, and the seal is only consulted at unseal time. Probe it several
# times across the restart window (sys/health is unauthenticated).
for _ in 1 2 3 4 5 6; do
  http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 --cacert "${VAULT_CA}" \
    "${VAULT_ADDR}/v1/sys/health?standbyok=true&perfstandbyok=true" || true)
  [[ "${http_code}" =~ ^(200|429|473)$ ]] || die "Cluster returned HTTP ${http_code:-none} while the seal Vault restarted"
  sleep 5
done
ok "Cluster kept serving during the seal Vault restart (last HTTP ${http_code})"

# Wait for seal Vault pod to restart
info "Waiting for seal Vault pod to be Running"
oc -n sg-vault-seal wait pod -l app.kubernetes.io/instance=vault-seal \
  --for=condition=Ready --timeout=120s 2>/dev/null || true

# Seal Vault restarts as sealed (Shamir 1/1)
sealed=$(curl -s --cacert "${VAULT_CA}" "${SEAL_ADDR}/v1/sys/health" | jq -r '.sealed' || true)
if [[ "${sealed}" == "true" ]]; then
  ok "Seal Vault is sealed after restart (expected) — running make unseal"
  make -C "${ROOT_DIR}" unseal
else
  die "Seal Vault is not sealed after its restart (sealed=${sealed:-unknown}); Shamir 1/1 must come back sealed"
fi

# Confirm seal Vault unsealed
sealed_after=$(curl -s --cacert "${VAULT_CA}" "${SEAL_ADDR}/v1/sys/health" | jq -r '.sealed' || true)
[[ "${sealed_after}" == "false" ]] || die "Seal Vault still sealed after unseal"

ok "Scenario 04 PASS: seal Vault restarted sealed, cluster kept serving, make unseal restored chain"
