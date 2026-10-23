#!/usr/bin/env bash
# Four reversible mutations, specific detection evidence, cleanup on failure.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../scripts/common.sh"
sg_lock "$@"
require_kubeconfig
require_cmd oc python3
exec python3 "${SCRIPT_DIR}/proof.py"
