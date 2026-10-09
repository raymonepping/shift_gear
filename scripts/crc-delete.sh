#!/usr/bin/env bash
# scripts/crc-delete.sh — Destroy the existing CRC VM, keeping the cache.
# Idempotent: exits 0 if no VM exists.
# Does NOT delete ~/.crc/cache or .secrets/crc/pull-secret.json.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd crc

STATUS=$(crc status --output json 2>/dev/null | jq -r '.crcStatus' 2>/dev/null || echo "Missing")

if [[ "${STATUS}" == "Missing" || "${STATUS}" == "No CRC instance"* ]]; then
  info "No CRC instance found; nothing to delete."
  exit 0
fi

info "CRC VM found (status: ${STATUS}) — deleting..."

# Stop first if running
if [[ "${STATUS}" == "Running" ]]; then
  info "Stopping CRC VM..."
  crc stop 2>/dev/null || true
fi

info "Deleting CRC VM..."
crc delete --force
ok "CRC VM deleted. Run 'make crc-up' to create a fresh instance."
info "Cache preserved at ~/.crc/cache ($(du -sh ~/.crc/cache 2>/dev/null | cut -f1 || echo '?'))."
