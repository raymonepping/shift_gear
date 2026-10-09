#!/usr/bin/env bash
# scripts/crc-down.sh — Stop the CRC VM. Substrate script — may reference crc.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

if command -v crc >/dev/null 2>&1; then
  info "Stopping CRC VM"
  crc stop || true
  ok "CRC stopped"
else
  warn "crc not found — skipping crc stop"
fi
