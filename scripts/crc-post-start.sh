#!/usr/bin/env bash
# scripts/crc-post-start.sh — keep the CRC node's clock honest after a start
# or a Mac sleep.
#
# vfkit pauses the VM while the Mac sleeps; the guest clock then lags by the
# length of the sleep (observed: 5 h 41 min). Consequences: the project CA
# looks "not yet valid" (every mTLS handshake to the seal agent fails), the
# seal agent's AppRole token expires in one jump (403 on transit/encrypt),
# projected SA tokens look expired, dynamic leases lapse.
#
# CRC 2.64 has no `crc ssh`; the supported way into the node is
# `oc debug node/<name> -- chroot /host`. This script:
#   1. measures the node's offset against the Mac's clock;
#   2. sets the node clock from the Mac when the offset exceeds 5 s (chrony
#      alone does not recover: with `makestep 1.0 3` it only steps at boot,
#      and observed it reporting 0 s offset while 6 h behind);
#   3. makes chrony step whenever needed from now on (`makestep 1.0 -1`,
#      `maxpoll 6`) and restarts it when the config changed.
# Idempotent; exits non-zero when it could not reach the node.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd crc
require_cmd oc
require_kubeconfig

state=$(crc status -o json 2>/dev/null | jq -r '.crcStatus // "Missing"' 2>/dev/null || echo Missing)
if [[ "${state}" != "Running" ]]; then
  warn "crc-post-start: CRC is not running (state=${state}); nothing to do"
  exit 0
fi

node=$(oc get nodes -o jsonpath='{.items[0].metadata.name}')
on_node() { timeout 180 oc debug "node/${node}" -q -- chroot /host sh -c "$1" 2>/dev/null; }

node_epoch=$(on_node 'date -u +%s') || die "crc-post-start: cannot reach node ${node} through oc debug"
offset=$(( $(date -u +%s) - node_epoch ))
info "Node ${node} clock offset: ${offset}s (positive = node behind the Mac)"

if (( offset > 5 || offset < -5 )); then
  on_node "date -u -s @$(date -u +%s) >/dev/null" || die "crc-post-start: setting the node clock failed"
  ok "Node clock set from the Mac (was ${offset}s off)"
fi

# shellcheck disable=SC2016  # runs on the node
result=$(on_node '
  conf=/etc/chrony.conf; changed=0
  if grep -q "^makestep " "$conf" && ! grep -q "^makestep 1.0 -1$" "$conf"; then
    sed -i "s/^makestep .*/makestep 1.0 -1/" "$conf"; changed=1
  elif ! grep -q "^makestep " "$conf"; then
    echo "makestep 1.0 -1" >>"$conf"; changed=1
  fi
  grep -q "^maxpoll 6$" "$conf" || { echo "maxpoll 6" >>"$conf"; changed=1; }
  if [ "$changed" = 1 ]; then systemctl restart chronyd; echo hardened; else echo unchanged; fi
') || die "crc-post-start: chrony configuration failed"
case "${result}" in
*hardened*) ok "chrony: makestep 1.0 -1, maxpoll 6 (restarted)" ;;
*) ok "chrony already hardened" ;;
esac
