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
#   3. permits later steps (`makestep 1.0 -1`), removes the invalid standalone
#      maxpoll directive and verifies that the time service actually runs.
# Idempotent; exits non-zero when it could not reach the node.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd oc
require_kubeconfig

if ! oc --request-timeout=10s whoami >/dev/null 2>&1; then
  die "crc-post-start: OpenShift API is unavailable; cannot verify node clock"
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
  # maxpoll is a server/pool option, never a standalone directive.
  if grep -q "^maxpoll " "$conf"; then
    sed -i "/^maxpoll /d" "$conf"; changed=1
  fi
  if [ "$changed" = 1 ] || ! systemctl is-active --quiet chronyd; then
    systemctl restart chronyd || exit 1
  fi
  systemctl is-active --quiet chronyd || exit 1
  chronyc tracking >/dev/null || exit 1
  echo active
') || die "crc-post-start: chrony configuration failed"
[[ "${result}" == *active* ]] || die "crc-post-start: chrony service verification failed"
ok "chrony: valid configuration and active service"
node_epoch=$(on_node 'date -u +%s') || die "crc-post-start: cannot verify repaired node clock"
offset=$(( $(date -u +%s) - node_epoch ))
(( offset >= -5 && offset <= 5 )) || die "crc-post-start: node still ${offset}s off after repair"
ok "Node clock verified within 5s of host"
