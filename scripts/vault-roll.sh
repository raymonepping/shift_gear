#!/usr/bin/env bash
# Roll one Raft member at a time, checking actual unsealed status and new UID.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
sg_lock "$@"
require_cmd oc jq timeout
require_kubeconfig
NS=sg-vault
mapfile -t all_pods < <(oc -n "${NS}" get pods -l app.kubernetes.io/name=vault -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
[[ ${#all_pods[@]} -eq 3 ]] || die "Expected three Raft members before rolling"

status() {
  timeout 8 oc --request-timeout=5s -n "${NS}" exec "$1" -- env VAULT_ADDR=https://127.0.0.1:8200 vault status -format=json 2>/dev/null
}
healthy() { status "$1" | jq -e '.initialized == true and .sealed == false' >/dev/null; }
leader() {
  local pod data
  for pod in "${all_pods[@]}"; do
    data="$(status "${pod}")" || continue
    if jq -e '.is_self == true and .sealed == false' >/dev/null <<<"${data}"; then printf '%s\n' "${pod}"; return 0; fi
  done
  return 1
}
for pod in "${all_pods[@]}"; do healthy "${pod}" || die "${pod} is not unsealed; refusing a roll"; done
active="$(leader)" || die "No current leader; refusing a roll"
info "Rolling standbys first, then ${active}"
order=()
for pod in "${all_pods[@]}"; do [[ "${pod}" == "${active}" ]] || order+=("${pod}"); done
order+=("${active}")
for pod in "${order[@]}"; do
  # Readiness deliberately accepts sealed bootstrap pods, so it cannot prove
  # Raft quorum. Every member must actually answer unsealed before deletion.
  for member in "${all_pods[@]}"; do healthy "${member}" || die "${member} unavailable; stopping before ${pod}"; done
  previous="$(oc -n "${NS}" get pod "${pod}" -o jsonpath='{.metadata.uid}')"
  oc -n "${NS}" delete pod "${pod}" --wait=false
  deadline=$((SECONDS + 180))
  joined=false
  while (( SECONDS < deadline )); do
    current="$(oc --request-timeout=5s -n "${NS}" get pod "${pod}" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)"
    if [[ -n "${current}" && "${current}" != "${previous}" ]] && healthy "${pod}"; then joined=true; break; fi
    sleep 2
  done
  [[ "${joined}" == true ]] || die "${pod} did not rejoin unsealed; remaining members were not rolled"
  ok "${pod} replaced and unsealed"
done
new_leader=""
deadline=$((SECONDS + 60))
while (( SECONDS < deadline )); do
  if new_leader="$(leader)"; then break; fi
  sleep 2
done
[[ -n "${new_leader}" ]] || die "No leader after roll"
python3 "${SCRIPT_DIR}/wait-raft.py"
ok "vault-roll complete — all three members unsealed; leader ${new_leader}"
