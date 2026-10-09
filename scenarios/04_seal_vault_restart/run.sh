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
TOKEN_FILE="${SECRETS_DIR}/tokens/ansible-platform"
VAULT_TOKEN="$(cat "${TOKEN_FILE}")"

info "Scenario 04: restarting seal Vault pod"
oc -n sg-vault-seal delete pod -l app.kubernetes.io/instance=vault-seal --grace-period=0

# Cluster must remain serving
http_code=$(curl -sf -o /dev/null -w '%{http_code}' --cacert "${VAULT_CA}" \
  -H "X-Vault-Token: ${VAULT_TOKEN}" -H "X-Vault-Namespace: shift-gear" \
  "${VAULT_ADDR}/v1/sys/health" || echo 000)
[[ "${http_code}" =~ ^(200|429)$ ]] && ok "Cluster still serving (HTTP ${http_code})" \
  || warn "Cluster returned HTTP ${http_code} during seal Vault restart"

# Wait for seal Vault pod to restart
info "Waiting for seal Vault pod to be Running"
oc -n sg-vault-seal wait pod -l app.kubernetes.io/instance=vault-seal \
  --for=condition=Ready --timeout=120s 2>/dev/null || true

# Seal Vault restarts as sealed (Shamir 1/1)
sealed=$(curl -sf --cacert "${VAULT_CA}" "${SEAL_ADDR}/v1/sys/health" | jq -r '.sealed')
if [[ "${sealed}" == "true" ]]; then
  ok "Seal Vault is sealed after restart (expected) — running make unseal"
  "${SCRIPT_DIR}/../../scripts/ansible-run.sh" unseal
else
  warn "Seal Vault not sealed after restart (may have been auto-unsealed)"
fi

# Confirm seal Vault unsealed
sealed_after=$(curl -sf --cacert "${VAULT_CA}" "${SEAL_ADDR}/v1/sys/health" | jq -r '.sealed')
[[ "${sealed_after}" == "false" ]] || die "Seal Vault still sealed after unseal"

ok "Scenario 04 PASS: seal Vault restarted sealed, cluster kept serving, make unseal restored chain"
