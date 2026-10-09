#!/usr/bin/env bash
# scripts/vault-roll.sh — Controlled rolling restart for the main Vault cluster.
# Strategy: scale down standbys one at a time (OnDelete), wait for Raft
# quorum after each; roll the active leader last.
# Requires: kubeconfig, oc, jq; VAULT_CACERT + token for health checks.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd oc jq

require_kubeconfig

NS="sg-vault"
QUORUM=2  # minimum voters needed while one pod is restarting

# Wait until at least $QUORUM Vault pods are healthy and unsealed
wait_quorum() {
  local retries=30 delay=10
  info "  waiting for ${QUORUM}+ healthy voters"
  for _ in $(seq 1 "${retries}"); do
    healthy=$(oc -n "${NS}" get pods -l app.kubernetes.io/name=vault \
      -o json 2>/dev/null | jq '[.items[] | select(.status.containerStatuses[0].ready==true)] | length')
    [[ "${healthy}" -ge "${QUORUM}" ]] && { ok "  quorum met (${healthy} healthy)"; return 0; }
    sleep "${delay}"
  done
  die "Timed out waiting for quorum (${QUORUM} healthy voters)"
}

# Get the active (leader) pod name
active_pod() {
  oc -n "${NS}" get pods -l app.kubernetes.io/name=vault -o name 2>/dev/null | \
    while read -r pod; do
      pod_name="${pod#pod/}"
      status=$(oc -n "${NS}" exec "${pod_name}" -- vault status -format=json 2>/dev/null | \
        jq -r '.is_self' 2>/dev/null || echo false)
      [[ "${status}" == "true" ]] && echo "${pod_name}" && return
    done
}

info "vault-roll: collecting Vault pods in ${NS}"
mapfile -t all_pods < <(oc -n "${NS}" get pods -l app.kubernetes.io/name=vault \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)

[[ ${#all_pods[@]} -gt 0 ]] || die "No Vault pods found in ${NS}"

leader="$(active_pod)"
[[ -n "${leader}" ]] || die "Could not determine active (leader) pod"

info "Leader is: ${leader}"
info "Rolling standbys first, then leader"

for pod in "${all_pods[@]}"; do
  [[ "${pod}" == "${leader}" ]] && continue
  info "  rolling standby: ${pod}"
  oc -n "${NS}" delete pod "${pod}" --wait=false
  sleep 5
  wait_quorum
  ok "  ${pod} rejoined"
done

info "  rolling leader: ${leader} (cluster will elect a new leader)"
oc -n "${NS}" delete pod "${leader}" --wait=false
sleep 10
wait_quorum

new_leader="$(active_pod)"
ok "vault-roll complete — new leader: ${new_leader:-unknown}"
