#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
# Keep the host awake for the lifetime of this controller, including child drills.
if [[ "$(uname -s)" == Darwin && "${SG_PROOF_AWAKE:-0}" != 1 ]] && command -v caffeinate >/dev/null 2>&1; then
  export SG_PROOF_AWAKE=1
  exec caffeinate -ims "${BASH}" "${BASH_SOURCE[0]}" "$@"
fi
sg_lock "$@"
if [[ "${1:-}" == --live ]]; then
  "${SCRIPT_DIR}/crc-post-start.sh"
fi
exec python3 "${SCRIPT_DIR}/release-proof.py" "$@"
