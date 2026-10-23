#!/usr/bin/env bash
# scripts/crc-down.sh — Stop the CRC VM. Substrate script — may reference crc.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

if command -v crc >/dev/null 2>&1; then
  info "Stopping CRC VM"
  "${SCRIPT_DIR}/crc-control.sh" stop
  pid_file="${HOME}/.crc/machines/crc/vfkit.pid"
  if [[ -s "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" 2>/dev/null; then
    die "CRC stop returned but the VM process remains running"
  fi
  ok "CRC stopped"
else
  die "crc not found — VM shutdown was not performed"
fi
