#!/usr/bin/env bash
# scripts/down.sh — Lifecycle: make down | make up | make reset
#
# down : scale all workloads to 0 (seal Vault last), then scripts/crc-down.sh.
#        NEVER deletes PVCs, Secrets or .secrets/.
# up   : scripts/crc-up.sh, scale seal Vault, unseal, seal agent, main Vault,
#        identity, workloads, app; then make verify.
#        If the seal agent cannot authenticate (expired secret-id > 24 h),
#        runs make agent to re-mint it first.
# reset: DESTRUCTIVE — requires typing 'shift-gear'. Deletes namespaces and
#        moves generated state to .secrets/archive/<timestamp>/. Keeps CRC VM.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd oc

action="${1:-}"
[[ -n "${action}" ]] || { echo "Usage: $0 down|up|reset" >&2; exit 1; }

require_kubeconfig

scale() {
  local ns="$1" selector="$2" replicas="$3"
  oc -n "${ns}" scale deployment --selector "${selector}" --replicas "${replicas}" 2>/dev/null || true
}

case "${action}" in

# ── down ──────────────────────────────────────────────────────────────────────
down)
  info "Scaling down — application namespaces first, seal Vault last"
  for ns in sg-app sg-workloads sg-identity; do
    info "  scale ${ns} → 0"
    oc -n "${ns}" scale deployment --all --replicas 0 2>/dev/null || true
  done
  info "  scale sg-vault → 0 (statefulset)"
  oc -n sg-vault scale statefulset vault --replicas 0 2>/dev/null || true
  info "  scale seal-agent → 0"
  oc -n sg-vault-seal scale deployment seal-agent --replicas 0 2>/dev/null || true
  info "  scale sg-vault-seal → 0 (statefulset)"
  oc -n sg-vault-seal scale statefulset vault-seal --replicas 0 2>/dev/null || true
  ok "All workloads scaled to 0"
  "${SCRIPT_DIR}/crc-down.sh"
  ok "down complete"
  ;;

# ── up ────────────────────────────────────────────────────────────────────────
up)
  info "Bringing the lab up"
  "${SCRIPT_DIR}/crc-up.sh"
  require_kubeconfig

  info "Scaling seal Vault up"
  oc -n sg-vault-seal scale statefulset vault-seal --replicas 1
  info "Waiting for seal Vault pod"
  oc -n sg-vault-seal wait pod -l app.kubernetes.io/instance=vault-seal \
    --for=condition=Ready --timeout=120s 2>/dev/null || true

  info "Unsealing seal Vault"
  "${SCRIPT_DIR}/ansible-run.sh" unseal

  info "Scaling seal-agent up"
  oc -n sg-vault-seal scale deployment seal-agent --replicas 1

  # If the agent cannot authenticate, the secret-id expired — re-mint it
  if ! oc -n sg-vault-seal wait deployment seal-agent \
      --for=condition=Available --timeout=60s 2>/dev/null; then
    warn "Seal agent not ready — secret-id may have expired. Running make agent..."
    "${SCRIPT_DIR}/ansible-run.sh" agent
  fi

  info "Scaling main Vault cluster up"
  oc -n sg-vault scale statefulset vault --replicas 3
  info "Waiting for Vault pods (auto-unseals through seal agent)"
  oc -n sg-vault wait pod -l app.kubernetes.io/name=vault \
    --for=condition=Ready --timeout=300s 2>/dev/null || true

  info "Scaling identity stack up"
  oc -n sg-identity scale deployment --all --replicas 1 2>/dev/null || true

  info "Scaling workloads up"
  oc -n sg-workloads scale deployment --all --replicas 1 2>/dev/null || true

  info "Scaling sg-app up"
  oc -n sg-app scale deployment --all --replicas 1 2>/dev/null || true

  info "Running make verify"
  make -C "${ROOT_DIR}" verify || warn "make verify: some checks failed — see output above"

  ok "up complete"
  ;;

# ── reset ─────────────────────────────────────────────────────────────────────
reset)
  printf '\033[31mDESTRUCTIVE RESET\033[0m — type "shift-gear" to confirm: '
  read -r confirm
  [[ "${confirm}" == "shift-gear" ]] || { warn "Aborted."; exit 1; }

  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  archive="${SECRETS_DIR}/archive/${ts}"
  mkdir -p "${archive}"

  info "Archiving generated state to ${archive}"
  for f in "${SECRETS_DIR}/seal-init.json" "${SECRETS_DIR}/vault-init.json"; do
    [[ -f "${f}" ]] && mv "${f}" "${archive}/" || true
  done
  [[ -d "${SECRETS_DIR}/tokens" ]] && mv "${SECRETS_DIR}/tokens" "${archive}/tokens" || true
  [[ -d "${BUILD_DIR}" ]] && mv "${BUILD_DIR}" "${archive}/build" || true

  info "Deleting OpenShift namespaces"
  for ns in sg-app sg-workloads sg-identity sg-vault sg-vault-seal; do
    oc delete namespace "${ns}" --ignore-not-found 2>/dev/null || true
  done

  ok "Reset complete — CRC VM preserved. Run 'make lab' to rebuild."
  ;;

*)
  echo "Usage: $0 down|up|reset" >&2
  exit 1
  ;;
esac
