#!/usr/bin/env bash
# scripts/down.sh — Lifecycle: make down | make up | make reset
#
# down : scale all workloads to 0 (seal Vault last), then scripts/crc-down.sh.
#        NEVER deletes PVCs, Secrets or .secrets/.
# up   : scripts/crc-up.sh, scale seal Vault, unseal, refresh seal tokens
#        (seal-init), seal agent (make agent re-mints expired secret-ids
#        before the agent starts), main Vault, refresh platform tokens
#        (bootstrap), identity, workloads, app; then make verify.
# reset: DESTRUCTIVE — requires typing 'shift-gear' (or CONFIRM=shift-gear; DRY_RUN=1 lists only). Deletes namespaces and
#        moves generated state to .secrets/archive/<timestamp>/. Keeps CRC VM.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
sg_lock "$@"

require_cmd oc

action="${1:-}"
[[ -n "${action}" ]] || { echo "Usage: $0 down|up|reset" >&2; exit 1; }

require_kubeconfig

# Namespaces of installed add-ons (ADR D17): labelled shift-gear/addon.
addon_namespaces() {
  oc get namespace -l shift-gear/addon -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
}

scale() {
  local ns="$1" selector="$2" replicas="$3"
  oc -n "${ns}" scale deployment --selector "${selector}" --replicas "${replicas}" 2>/dev/null
}

case "${action}" in

# ── down ──────────────────────────────────────────────────────────────────────
down)
  "${SCRIPT_DIR}/crc-health.sh" --require-control
  info "Scaling down — application namespaces first, seal Vault last"
  # Add-ons (ADR D17; namespaces labelled shift-gear/addon) stop before Vault
  # does. The rotation add-on is stateless (one CAS write per rotation), so
  # there is nothing to drain.
  for ns in $(addon_namespaces); do
    info "  scale ${ns} → 0 (add-on)"
    oc -n "${ns}" scale deployment --all --replicas 0 2>/dev/null
  done
  for ns in sg-app sg-workloads sg-identity; do
    info "  scale ${ns} → 0"
    oc -n "${ns}" scale deployment --all --replicas 0 2>/dev/null
  done
  info "  scale sg-vault → 0 (statefulset)"
  oc -n sg-vault scale statefulset vault --replicas 0 2>/dev/null
  info "  scale seal-agent → 0"
  oc -n sg-vault-seal scale deployment seal-agent --replicas 0 2>/dev/null
  info "  scale sg-vault-seal → 0 (statefulset)"
  oc -n sg-vault-seal scale statefulset vault-seal --replicas 0 2>/dev/null
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
    --for=condition=Ready --timeout=180s

  info "Unsealing seal Vault"
  "${SCRIPT_DIR}/ansible-run.sh" unseal

  # The bootstrap tokens are periodic (24 h); a lab left down longer comes
  # back with refused tokens. seal-init renews live ones and re-issues refused
  # ones through their token role (init and unseal are guarded no-ops).
  info "Refreshing seal Vault bootstrap tokens"
  "${SCRIPT_DIR}/ansible-run.sh" seal-init

  # Repair expired secret-ids BEFORE the agent starts: an agent started on a
  # stale ID fails its logins and locks the AppRole, so the fresh ID is then
  # refused too. The agent phase scales seal-agent up (restarting it when it
  # was already running) and proves Transit before main Vault unseals.
  info "Starting seal-agent with verified credentials"
  "${SCRIPT_DIR}/ansible-run.sh" agent
  oc -n sg-vault-seal rollout status deployment/seal-agent --timeout=180s

  info "Scaling main Vault cluster up"
  oc -n sg-vault scale statefulset vault --replicas 3
  info "Waiting for Vault pods (auto-unseals through seal agent)"
  oc -n sg-vault wait pod -l app.kubernetes.io/name=vault \
    --for=condition=Ready --timeout=300s
  # Same 24 h period as the seal tokens; wait-raft.py and verify use them.
  info "Refreshing platform bootstrap tokens"
  "${SCRIPT_DIR}/ansible-run.sh" bootstrap
  python3 "${SCRIPT_DIR}/wait-raft.py" --unsealed

  info "Scaling identity stack up"
  oc -n sg-identity scale deployment --all --replicas 1
  oc -n sg-identity wait deployment --all --for=condition=Available --timeout=300s

  info "Scaling workloads up"
  oc -n sg-workloads scale deployment --all --replicas 1
  oc -n sg-workloads wait deployment --all --for=condition=Available --timeout=300s

  info "Scaling sg-app up"
  oc -n sg-app scale deployment --all --replicas 1
  # Init auth can retain a five-minute backoff from the sealed interval.
  # Delete the pod instead of `rollout restart`: the Deployment is Terraform's,
  # and a restartedAt annotation on its template is drift.
  if [[ "$(oc -n sg-app get deployment agent-demo -o jsonpath='{.status.availableReplicas}')" != 1 ]]; then
    oc -n sg-app delete pod -l app.kubernetes.io/name=agent-demo --wait=false
  fi
  oc -n sg-app wait deployment --all --for=condition=Available --timeout=300s

  info "Waiting for Vault Secrets Operator reconciliation"
  # VSO can park a secret that failed while main Vault was down and never
  # requeue it; touching an annotation forces a fresh reconcile.
  oc -n sg-workloads annotate vaultstaticsecret/app-config vaultdynamicsecret/db-creds \
    shift-gear/reconcile-nudge="$(date -u +%s)" --overwrite >/dev/null
  oc -n sg-workloads wait vaultstaticsecret/app-config \
    --for=condition=SecretSynced --timeout=180s
  oc -n sg-workloads wait vaultdynamicsecret/db-creds \
    --for=condition=SecretSynced --timeout=180s

  for ns in $(addon_namespaces); do
    info "Scaling add-on ${ns} up"
    oc -n "${ns}" scale deployment --all --replicas 1
    oc -n "${ns}" wait deployment --all --for=condition=Available --timeout=180s
  done

  info "Running make verify"
  VERIFY_SCOPE=runtime make -C "${ROOT_DIR}" verify

  ok "up complete"
  ;;

# ── reset ─────────────────────────────────────────────────────────────────────
reset)
  # Moves (never deletes) everything a fresh cluster must not inherit into
  # .secrets/archive/<timestamp>/, then deletes the lab namespaces.
  # Kept on purpose (the operator's, or valid across clusters): .env, the pull
  # secret, the kubeconfig the cluster scripts manage (.secrets/kube/config)
  # and the lab CA (.secrets/tls/ca.key, ca.srl, pub/ca.pem), so 'make trust'
  # survives a reset. Leaf certificates are regenerated by 'make lab'.
  #   DRY_RUN=1 make reset            list what would happen, change nothing
  #   CONFIRM=shift-gear make reset   non-interactive confirmation
  targets=()
  for f in "${SECRETS_DIR}/seal-init.json" "${SECRETS_DIR}/vault-init.json" \
    "${SECRETS_DIR}/tokens" "${SECRETS_DIR}/terraform" "${SECRETS_DIR}/vault" \
    "${SECRETS_DIR}/kube/ingress-ca.pem" "${BUILD_DIR}"; do
    [[ -e "${f}" ]] && targets+=("${f}")
  done
  while IFS= read -r f; do targets+=("${f}"); done < <(
    find "${SECRETS_DIR}/tls" -maxdepth 2 -type f \( -name '*.key' -o -name '*.crt' \) \
      ! -name 'ca.key' 2>/dev/null | sort)
  namespaces=(sg-app sg-workloads sg-identity sg-vault sg-vault-seal)
  while IFS= read -r ns; do [[ -n "${ns}" ]] && namespaces+=("${ns}"); done < <(addon_namespaces)

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    info "DRY RUN: make reset would move into .secrets/archive/<timestamp>/:"
    for f in "${targets[@]}"; do printf '  %s\n' "${f#"${ROOT_DIR}"/}"; done
    info "and delete the namespaces: ${namespaces[*]}"
    info "and the cluster-scoped objects Terraform owns: Subscription + CSV vault-secrets-operator, ClusterRoleBinding vault-token-reviewer"
    info "Kept: .env, the pull secret, .secrets/kube/config, the lab CA. Nothing changed."
    exit 0
  fi

  if [[ "${CONFIRM:-}" != "shift-gear" ]]; then
    printf '\033[31mDESTRUCTIVE RESET\033[0m — type "shift-gear" to confirm: '
    read -r confirm
    [[ "${confirm}" == "shift-gear" ]] || { warn "Aborted."; exit 1; }
  fi

  target_id="$(oc --request-timeout=5s get namespace kube-system -o jsonpath='{.metadata.uid}')"
  [[ -n "${target_id}" ]] || die "Cannot verify destructive target"
  [[ "${CONFIRM_CLUSTER_ID:-}" == "${target_id}" ]] || die "Set CONFIRM_CLUSTER_ID to the displayed target UID from make doctor before reset: ${target_id}"
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  archive="${SECRETS_DIR}/archive/${ts}"
  mkdir -p "${archive}"
  chmod 700 "${SECRETS_DIR}/archive" "${archive}"

  info "Archiving generated state to ${archive#"${ROOT_DIR}"/}"
  for f in "${targets[@]}"; do
    rel="${f#"${ROOT_DIR}"/}"
    mkdir -p "${archive}/$(dirname "${rel}")"
    mv "${f}" "${archive}/${rel}"
  done

  info "Deleting OpenShift namespaces"
  for ns in "${namespaces[@]}"; do
    oc delete namespace "${ns}" --ignore-not-found 2>/dev/null
  done

  # Cluster-scoped objects Terraform owns outlive the namespaces; with the
  # state archived, the next apply would fail on "already exists".
  info "Deleting the cluster-scoped objects Terraform owns"
  csv="$(oc -n openshift-operators get subscription vault-secrets-operator \
    -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"
  oc -n openshift-operators delete subscription vault-secrets-operator --ignore-not-found 2>/dev/null
  [[ -n "${csv}" ]] && oc -n openshift-operators delete csv "${csv}" --ignore-not-found 2>/dev/null
  oc delete clusterrolebinding vault-token-reviewer --ignore-not-found 2>/dev/null

  ok "Reset complete — CRC VM preserved, lab CA kept ('make trust' still applies)."
  info "Next: 'make lab' to rebuild on this VM, or 'make crc-reset && make lab' for a fresh VM."
  ;;

*)
  echo "Usage: $0 down|up|reset" >&2
  exit 1
  ;;
esac
