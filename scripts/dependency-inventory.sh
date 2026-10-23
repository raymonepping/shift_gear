#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
require_kubeconfig
exec python3 "${SCRIPT_DIR}/dependency-inventory.py"
