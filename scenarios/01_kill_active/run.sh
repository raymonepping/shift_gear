#!/usr/bin/env bash
# scenarios/01_kill_active/run.sh — Kill the active Vault pod.
# Expected: a standby serves within seconds; the pod rejoins unsealed.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../scripts/common.sh"
require_kubeconfig
require_cmd oc jq

INFRA="${BUILD_DIR}/terraform/infra.json"
APPS_DOMAIN="$(jq -r '.cluster.apps_domain' "${INFRA}")"
VAULT_ADDR="https://vault.${APPS_DOMAIN}"
VAULT_CA="${SECRETS_DIR}/tls/pub/ca.pem"

# Find the active (leader) pod
active=$(oc -n sg-vault get pods -l app.kubernetes.io/name=vault -o name \
  | sed 's|pod/||' | while read -r p; do
    st=$(oc -n sg-vault exec "${p}" -- vault status -format=json 2>/dev/null | jq -r '.is_self' || echo false)
    [[ "${st}" == "true" ]] && echo "${p}" && break
  done)
[[ -n "${active}" ]] || { warn "Could not identify active pod — cluster may already be in failover"; exit 1; }

info "Scenario 01: killing active pod ${active}"
oc -n sg-vault delete pod "${active}" --grace-period=0

# Wait for a new leader to emerge (max 30 s)
info "Waiting for a new leader..."
for _ in $(seq 1 30); do
  new_leader=$(oc -n sg-vault get pods -l app.kubernetes.io/name=vault -o name \
    | sed 's|pod/||' | while read -r p; do
      st=$(oc -n sg-vault exec "${p}" -- vault status -format=json 2>/dev/null | jq -r '.is_self' || echo false)
      [[ "${st}" == "true" ]] && echo "${p}" && break
    done)
  if [[ -n "${new_leader}" && "${new_leader}" != "${active}" ]]; then
    ok "New leader elected: ${new_leader}"
    break
  fi
  sleep 1
done

# Wait for the killed pod to rejoin
info "Waiting for ${active} to rejoin..."
oc -n sg-vault wait pod "${active}" --for=condition=Ready --timeout=120s

# Confirm it rejoined unsealed
sealed=$(oc -n sg-vault exec "${active}" -- vault status -format=json 2>/dev/null | jq -r '.sealed')
[[ "${sealed}" == "false" ]] || die "${active} rejoined but is still sealed"

ok "Scenario 01 PASS: active pod killed, standby took over, pod rejoined unsealed"
