#!/usr/bin/env bash
# Keep VM liveness separate from daemon/setup/control status. Read-only.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
pid_file="${HOME}/.crc/machines/crc/vfkit.pid"
if [[ -s "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" 2>/dev/null; then
  printf 'CRC VM process: running\n'
else
  printf 'CRC VM process: absent\n'
fi
if command -v crc >/dev/null 2>&1 && timeout 20 crc status >/dev/null 2>&1; then
  printf 'CRC control/status: available\n'
else
  printf 'CRC control/status: unavailable (does not imply the VM or API is down)\n'
  [[ "${1:-}" != --require-control ]] || die "CRC control preflight failed; workloads have not been stopped. Repair CRC control before lifecycle testing."
fi
