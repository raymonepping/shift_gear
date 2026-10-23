#!/usr/bin/env bash
# Retry publication without repeating successful provisioning.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
require_kubeconfig
sg_lock "$@"
[[ "$(jq -r .provisioning "${BUILD_DIR}/run.json")" == success ]] || die "No completed provisioning run to publish"
export SG_RUN_ID SG_CLUSTER_ID
SG_RUN_ID="$(jq -r .runId "${BUILD_DIR}/run.json")"
SG_CLUSTER_ID="$(jq -r .clusterId "${BUILD_DIR}/run.json")"
actual="$(oc --request-timeout=5s get namespace kube-system -o jsonpath='{.metadata.uid}')"
[[ "${actual}" == "${SG_CLUSTER_ID}" ]] || die "Target cluster changed; refusing stale publication"
trap 'python3 "${SCRIPT_DIR}/run-record.py" publication failed; python3 "${SCRIPT_DIR}/run-record.py" publish-status' ERR
"${SCRIPT_DIR}/ansible-run.sh" ux
python3 "${SCRIPT_DIR}/run-record.py" publication success
python3 "${SCRIPT_DIR}/run-record.py" publish-status
cp "${BUILD_DIR}/convergence.json" "${BUILD_DIR}/last-success.json"
