#!/usr/bin/env bash
# scripts/crc-delete.sh — Destroy the existing CRC VM, keeping the cache.
# Idempotent: exits 0 if no VM exists.
# Does NOT delete ~/.crc/cache or .secrets/crc/pull-secret.json.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd crc

pid_file="${HOME}/.crc/machines/crc/vfkit.pid"
if [[ -s "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" 2>/dev/null; then
  STATUS="Running"
elif [[ -d "${HOME}/.crc/machines/crc" ]]; then
  STATUS="Stopped"
else
  STATUS="Missing"
fi

if [[ "${STATUS}" == "Missing" || "${STATUS}" == "No CRC instance"* ]]; then
  info "No CRC instance found; nothing to delete."
  exit 0
fi

info "CRC VM found (status: ${STATUS}) — deleting..."

# Stop first if running
if [[ "${STATUS}" == "Running" ]]; then
  info "Stopping CRC VM..."
  "${SCRIPT_DIR}/crc-control.sh" stop
fi

info "Deleting CRC VM..."
"${SCRIPT_DIR}/crc-control.sh" delete --force
ok "CRC VM deleted. Run 'make crc-up' to create a fresh instance."
info "Cache preserved at ~/.crc/cache ($(du -sh ~/.crc/cache 2>/dev/null | cut -f1 || echo '?'))."
