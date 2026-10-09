#!/usr/bin/env bash
# scenarios/02_restart_seal_agent/run.sh — Restart the seal agent.
# Expected: the cluster keeps serving; the agent re-authenticates.
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

info "Scenario 02: deleting seal-agent pod to force restart"
oc -n sg-vault-seal delete pod -l app.kubernetes.io/name=seal-agent --grace-period=0

# Cluster must still serve during agent restart
info "Verifying cluster still serves during agent restart"
http_code=$(curl -sf -o /dev/null -w '%{http_code}' --cacert "${VAULT_CA}" \
  -H "X-Vault-Token: ${VAULT_TOKEN}" -H "X-Vault-Namespace: shift-gear" \
  "${VAULT_ADDR}/v1/sys/health" || echo 000)
[[ "${http_code}" =~ ^(200|429)$ ]] || die "Cluster not serving during agent restart (HTTP ${http_code})"
ok "Cluster serving during agent restart (HTTP ${http_code})"

# Wait for the agent to come back
info "Waiting for seal-agent to become Available"
oc -n sg-vault-seal wait deployment seal-agent --for=condition=Available --timeout=90s
ok "Seal agent back Available"

# Confirm cluster still healthy
http_code=$(curl -sf -o /dev/null -w '%{http_code}' --cacert "${VAULT_CA}" \
  -H "X-Vault-Token: ${VAULT_TOKEN}" -H "X-Vault-Namespace: shift-gear" \
  "${VAULT_ADDR}/v1/sys/health" || echo 000)
[[ "${http_code}" =~ ^(200|429)$ ]] || die "Cluster not healthy after agent restart (HTTP ${http_code})"

ok "Scenario 02 PASS: seal agent restarted, cluster kept serving, agent re-authenticated"
