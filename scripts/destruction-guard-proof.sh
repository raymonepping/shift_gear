#!/usr/bin/env bash
# A refused plan is not an apply. No resource is destroyed.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
sg_lock "$@"
umask 077
mkdir -p "${CACHE_DIR}/should"
log_file="${CACHE_DIR}/should/destruction-guard.log"
set +e
"${SCRIPT_DIR}/tf-run.sh" platform plan -destroy -no-color >"${log_file}" 2>&1
result=$?
set -e
if [[ "${result}" -ne 1 ]] || ! grep -q 'prevent_destroy' "${log_file}" || ! grep -q 'Instance cannot be destroyed' "${log_file}"; then
  die "Destruction guard not established; inspect the private plan log. No apply occurred."
fi
python3 - "${BUILD_DIR}/destruction-guard-proof.json" <<'PY'
import datetime as dt
import json
import sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({'result': 'pass', 'at': dt.datetime.now(dt.timezone.utc).isoformat(), 'destroyPlanRefused': True, 'applyExecuted': False}, indent=2) + '\n')
PY
ok "Destructive platform plan refused by prevent_destroy; no apply executed"
