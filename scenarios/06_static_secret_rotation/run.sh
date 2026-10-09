#!/usr/bin/env bash
# scenarios/06_static_secret_rotation/run.sh — make wl-a-rotate.
# Expected: VSO syncs the new KV version within ~30 s; workload-a rolls.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../scripts/common.sh"
require_kubeconfig
require_cmd oc jq

# Record current workload-a pod
before_pod=$(oc -n sg-workloads get pod -l app.kubernetes.io/name=workload-a \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
[[ -n "${before_pod}" ]] || die "workload-a pod not found"
info "Scenario 06: workload-a current pod: ${before_pod}"

info "  Writing new app-config version (make wl-a-rotate)"
make -C "${ROOT_DIR}" wl-a-rotate

# Wait up to 90 s for VSO to sync and workload-a to roll
info "  Waiting for workload-a to roll (VSO refreshAfter=30s)"
deadline=$(($(date +%s) + 90))
new_pod=""
while [[ $(date +%s) -lt ${deadline} ]]; do
  new_pod=$(oc -n sg-workloads get pod -l app.kubernetes.io/name=workload-a \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  [[ -n "${new_pod}" && "${new_pod}" != "${before_pod}" ]] && break
  sleep 5
done

if [[ -n "${new_pod}" && "${new_pod}" != "${before_pod}" ]]; then
  ok "workload-a rolled: ${before_pod} → ${new_pod}"
else
  die "workload-a did not roll within 90 s — current pod: ${new_pod:-none}"
fi

ok "Scenario 06 PASS: app-config updated, VSO synced, workload-a rolled"
