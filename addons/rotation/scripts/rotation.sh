#!/usr/bin/env bash
# addons/rotation/scripts/rotation.sh — lifecycle of the KV rotation add-on.
#
#   rotation.sh up|down|status|history|rotate|read|report|logs|plan|restart|validate|test [args]
#
# Orchestration only: Terraform (scripts/tf-run.sh rotation …) owns the
# objects, the add-on playbooks own Vault configuration and proof, the CLI
# (addons/rotation/cli/rotation_cli.py) reads Vault. Values are never printed
# except by `history` with REVEAL=1.
set -euo pipefail
ADDON_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ansible-env.sh
source "${ADDON_DIR}/../../scripts/ansible-env.sh"

export ANSIBLE_ROLES_PATH="${ADDON_DIR}/ansible/roles:${ROOT_DIR}/ansible/roles"
# Add-on phases never appear on the core Layers page.
export SG_STATS_DIR="${BUILD_DIR}/addons/rotation/ansible-stats"
mkdir -p "${BUILD_DIR}/addons/rotation" "${SG_STATS_DIR}"

TF="${ROOT_DIR}/scripts/tf-run.sh"
NS="sg-rotation"
STATE="${SECRETS_DIR}/terraform/rotation/terraform.tfstate"
PY="$(head -1 "$(readlink -f "$(command -v ansible-playbook)")" | sed 's/^#!//' | tr -d ' ')"
CLI=("${PY}" "${ADDON_DIR}/cli/rotation_cli.py")

playbook() {
  local name="$1"
  shift
  (cd "${ROOT_DIR}" && SG_PHASE="rotation-${name}" ansible-playbook "${ADDON_DIR}/ansible/rotation-${name}.yml" "$@" </dev/null)
}

installed() { oc get namespace "${NS}" >/dev/null 2>&1; }
state_has_resources() { [[ -s "${STATE}" ]] && [[ "$(jq '.resources | length' "${STATE}" 2>/dev/null || echo 0)" -gt 0 ]]; }

controller_state() {
  if ! installed; then echo "not installed"; return; fi
  if oc -n "${NS}" get deploy rotation-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q '^1$'; then
    echo "running"
  else
    echo "not ready"
  fi
}

cmd="${1:-}"
[[ -n "${cmd}" ]] || die "usage: rotation.sh up|down|status|history|rotate|read|report|logs|plan|restart|validate|test"
shift

case "${cmd}" in
up)
  info "KV rotation add-on: preflight"
  playbook preflight
  info "KV rotation add-on: Vault configuration (auth role, identity groups)"
  playbook configure
  info "KV rotation add-on: Terraform (namespace, controller, policies, NetworkPolicies)"
  "${TF}" rotation apply -no-color >"${BUILD_DIR}/addons/rotation/tf-apply.log" 2>&1 ||
    { tail -40 "${BUILD_DIR}/addons/rotation/tf-apply.log" >&2; die "terraform apply (rotation) failed — log: .build/addons/rotation/tf-apply.log"; }
  grep -E '^(Apply complete|No changes)' "${BUILD_DIR}/addons/rotation/tf-apply.log" || true
  info "KV rotation add-on: proof (onboarded, enforced, one rotation observed, inheritance)"
  playbook verify
  "${CLI[@]}" status || true
  ok "KV rotation add-on is up — try: make rotation-history SECRET=api-key/demo"
  ;;

down)
  if ! installed && ! state_has_resources; then
    playbook down >/dev/null
    ok "KV rotation add-on not installed — nothing to remove"
    exit 0
  fi
  info "KV rotation add-on: Terraform destroy (namespace, controller, policies, NetworkPolicies)"
  "${TF}" rotation destroy-auto -no-color >"${BUILD_DIR}/addons/rotation/tf-destroy.log" 2>&1 ||
    { tail -40 "${BUILD_DIR}/addons/rotation/tf-destroy.log" >&2; die "terraform destroy (rotation) failed"; }
  grep -E '^Destroy complete' "${BUILD_DIR}/addons/rotation/tf-destroy.log" || true
  info "KV rotation add-on: remove Vault configuration (auth role, identity groups)"
  playbook down
  info "Kept in Vault (history and values survive removal):"
  ROTATION_CONTROLLER_STATE="not installed" "${CLI[@]}" status || true
  info "Core check after removal"
  for root in foundation platform; do "${TF}" "${root}" drift -no-color | tail -1; done
  ok "KV rotation add-on removed — bring it back with: make rotation-up"
  ;;

status)
  state="$(controller_state)"
  echo "controller: ${state}"
  if [[ "${state}" == running ]]; then
    oc -n "${NS}" exec deploy/rotation-controller -c controller -- python3 -c \
      "import json,urllib.request;s=json.load(urllib.request.urlopen('http://127.0.0.1:8080/status',timeout=5))['controller'];print('events: %s   usage: %s   last loop: %s   identity: %s' % (s['events'], 'available' if s['usage']['available'] else 'not available', s['last_loop'], s['identity']))" \
      2>/dev/null || echo "status endpoint not answering"
  fi
  rc=0
  ROTATION_CONTROLLER_STATE="${state}" "${CLI[@]}" status || rc=$?
  [[ "${state}" == "not installed" ]] && exit 2
  exit "${rc}"
  ;;

history | rotate | read)
  [[ -n "${SECRET:-}" ]] || die "usage: make rotation-${cmd} SECRET=<type>/<name>   (e.g. SECRET=api-key/demo)"
  args=("${cmd}" "${SECRET}")
  [[ "${cmd}" == history && "${REVEAL:-0}" == 1 ]] && args+=(--reveal)
  [[ "${cmd}" == rotate && -n "${REASON:-}" ]] && args+=(--reason "${REASON}")
  exec "${CLI[@]}" "${args[@]}"
  ;;

report)
  ROTATION_CONTROLLER_STATE="$(controller_state)" exec "${CLI[@]}" report
  ;;

logs)
  installed || die "KV rotation add-on not installed"
  container="controller"
  case "${C:-}" in agent) container="vault-agent" ;; events) container="vault-events" ;; esac
  follow=()
  [[ "${F:-0}" == 1 ]] && follow=(-f)
  exec oc -n "${NS}" logs deploy/rotation-controller -c "${container}" --tail=200 ${follow[@]+"${follow[@]}"}
  ;;

plan)
  "${TF}" rotation plan -no-color | grep -E '^  # |^Plan:|^No changes' || true
  playbook configure --check --diff
  ;;

restart)
  installed || die "KV rotation add-on not installed"
  # Delete the pod instead of `rollout restart`: the Deployment is Terraform's (no drift).
  oc -n "${NS}" delete pod -l app.kubernetes.io/name=rotation-controller --wait=true
  oc -n "${NS}" wait pod -l app.kubernetes.io/name=rotation-controller --for=condition=Ready --timeout=180s
  ;;

validate)
  "${ADDON_DIR}/scripts/validate.sh"
  ;;

test)
  exec "${PY}" -u "${ADDON_DIR}/tests/live/run.py" "$@"
  ;;

*)
  die "unknown command: ${cmd}"
  ;;
esac
