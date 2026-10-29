#!/usr/bin/env bash
# scenarios/10_kv_rotation/run.sh — watch a KV v2 value rotate inside Vault.
# Question: does the KV rotation add-on (ADR D17) turn api-key/demo from X into
# Y into Z on its schedule, with each step a new KV v2 version and a history
# record? Prints fingerprints only, never a value. Changes nothing itself.
# Skips cleanly when the add-on is not installed.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../scripts/common.sh"
require_kubeconfig
require_cmd oc

if ! oc get namespace sg-rotation >/dev/null 2>&1; then
  warn "SKIP: the KV rotation add-on is not installed (make rotation-up)"
  exit 0
fi

SECRET="${SECRET:-api-key/demo}"
WANT="${ROTATIONS:-2}"
PY="$(head -1 "$(readlink -f "$(command -v ansible-playbook)")" | sed 's/^#!//' | tr -d ' ')"
CLI=("${PY}" "${ROOT_DIR}/addons/rotation/cli/rotation_cli.py")

version() { "${CLI[@]}" history "${SECRET}" | awk 'NR==3 {sub(/^v/, "", $1); print $1}'; }

start="$(version)"
[[ "${start}" =~ ^[0-9]+$ ]] || die "Precondition: ${SECRET} is not onboarded yet"
info "Watching ${SECRET} from v${start}; waiting for ${WANT} scheduled rotations (about ${WANT} minute(s))"
deadline=$((SECONDS + 90 * WANT))
while (( SECONDS < deadline )); do
  now="$(version)"
  (( now >= start + WANT )) && break
  sleep 5
done
"${CLI[@]}" history "${SECRET}" | head -$((WANT + 3))
end="$(version)"
if (( end >= start + WANT )); then
  ok "PASS: ${SECRET} rotated v${start} -> v${end} inside Vault (each step a KV v2 version with a record)"
else
  die "FAIL: ${SECRET} stayed at v${end} (expected >= v$((start + WANT))) — make rotation-status"
fi
