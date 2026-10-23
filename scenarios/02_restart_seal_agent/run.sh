#!/usr/bin/env bash
# scenarios/02_restart_seal_agent/run.sh — Restart the seal agent.
# Expected: the cluster keeps serving; the agent re-authenticates.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../scripts/common.sh"
sg_lock "$@"
require_kubeconfig
require_cmd oc jq

INFRA="${BUILD_DIR}/terraform/infra.json"
APPS_DOMAIN="$(jq -r '.cluster.apps_domain' "${INFRA}")"
VAULT_ADDR="https://vault.${APPS_DOMAIN}"
VAULT_CA="${SECRETS_DIR}/tls/pub/ca.pem"

before_uid=$(oc -n sg-vault-seal get pod -l app.kubernetes.io/name=seal-agent -o jsonpath='{.items[0].metadata.uid}')
[[ -n "${before_uid}" ]] || die "seal-agent pod not found"
info "Scenario 02: deleting seal-agent pod to force restart"
oc -n sg-vault-seal delete pod -l app.kubernetes.io/name=seal-agent --grace-period=0

# Cluster must still serve during agent restart
info "Verifying cluster still serves during agent restart"
http_code=$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' --cacert "${VAULT_CA}" \
  "${VAULT_ADDR}/v1/sys/health?standbyok=true&perfstandbyok=true" || true)
[[ "${http_code}" =~ ^(200|429)$ ]] || die "Cluster not serving during agent restart (HTTP ${http_code})"
ok "Cluster serving during agent restart (HTTP ${http_code})"

# Wait for the agent to come back
info "Waiting for seal-agent to become Available"
deadline=$(($(date +%s) + 90))
new_uid=""
while [[ $(date +%s) -lt ${deadline} ]]; do
  new_uid=$(oc -n sg-vault-seal get pods -l app.kubernetes.io/name=seal-agent -o json | \
    jq -r --arg old "${before_uid}" '.items[] | select(.metadata.uid != $old) | select(any(.status.conditions[]?; .type == "Ready" and .status == "True")) | .metadata.uid' | head -1)
  [[ -n "${new_uid}" ]] && break
  sleep 2
done
[[ -n "${new_uid}" ]] || die "No replacement Ready seal-agent pod within 90s"
new_pod=$(oc -n sg-vault-seal get pods -l app.kubernetes.io/name=seal-agent -o json | \
  jq -r --arg uid "${new_uid}" '.items[] | select(.metadata.uid == $uid) | .metadata.name')
oc -n sg-vault-seal logs "${new_pod}" -c seal-agent | grep -q 'authentication successful' || die "Replacement seal agent has not authenticated"
ok "Seal agent back Available and authenticated"

# Confirm cluster still healthy
http_code=$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' --cacert "${VAULT_CA}" \
  "${VAULT_ADDR}/v1/sys/health?standbyok=true&perfstandbyok=true" || true)
[[ "${http_code}" =~ ^(200|429)$ ]] || die "Cluster not healthy after agent restart (HTTP ${http_code})"

ok "Scenario 02 PASS: seal agent restarted, cluster kept serving, agent re-authenticated"
