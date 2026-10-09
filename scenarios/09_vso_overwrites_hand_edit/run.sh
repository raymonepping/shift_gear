#!/usr/bin/env bash
# scenarios/09_vso_overwrites_hand_edit/run.sh — edit a VSO-owned Secret by hand.
# Question: does VSO put the Vault value back, and how fast?
# Never writes to Vault and never prints a secret value: the Secret is
# compared by a hash of its data. Leaves the lab as it found it, even on FAIL.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../scripts/common.sh"
require_kubeconfig
require_cmd oc jq shasum

NS=sg-workloads
SECRET=app-config
KEY=log_level
MARKER=hand-edited
TIMEOUT="${TIMEOUT:-90}"

data_hash() { oc -n "${NS}" get secret "${SECRET}" -o json | jq -cS '.data' | shasum -a 256 | cut -d' ' -f1; }
current_value() { oc -n "${NS}" get secret "${SECRET}" -o jsonpath="{.data.${KEY}}" | base64 -d; }

# Fallback used only when VSO does not restore the Secret: force a resync the
# way sg_configure does, so a failed run never leaves the lab broken.
restore() {
  oc -n "${NS}" annotate vaultstaticsecret "${SECRET}" --overwrite \
    "shift-gear/seeded-at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null

  for _ in $(seq 1 20); do
    [[ "$(data_hash)" == "${before}" ]] && return 0
    sleep 3
  done
  return 1
}

synced="$(oc -n "${NS}" get vaultstaticsecret "${SECRET}" -o json |
  jq -r '[.status.conditions[]? | select(.type == "SecretSynced") | .status] | first // "Unknown"')"
[[ "${synced}" == "True" ]] || die "Precondition: VaultStaticSecret ${SECRET} is not synced (SecretSynced=${synced})"
before="$(data_hash)"
[[ "$(current_value)" != "${MARKER}" ]] || die "Precondition: ${SECRET} already carries the marker; run 'make configure'"
info "Scenario 09: ${NS}/${SECRET} synced, data hash ${before:0:12}"

info "  editing ${KEY} by hand (oc patch)"
oc -n "${NS}" patch secret "${SECRET}" --type merge \
  -p "{\"data\":{\"${KEY}\":\"$(printf '%s' "${MARKER}" | base64)\"}}" >/dev/null
[[ "$(current_value)" == "${MARKER}" ]] || die "the hand edit did not apply"
start=$(date +%s)

info "  waiting up to ${TIMEOUT}s for VSO to restore it"
restored=false
while (($(date +%s) - start < TIMEOUT)); do
  if [[ "$(data_hash)" == "${before}" ]]; then restored=true; break; fi
  sleep 3
done
took=$(($(date +%s) - start))

if [[ "${restored}" == "true" ]]; then
  ok "VSO restored ${SECRET} after ${took}s; the marker is gone"
  ok "Scenario 09 PASS: VSO overwrites a hand-edited Secret"
  exit 0
fi

printf '\033[31m FAIL\033[0m VSO did not restore %s within %ss (the marker is still there)\n' "${SECRET}" "${TIMEOUT}" >&2
if restore; then
  info "  restored by a forced resync (VaultStaticSecret annotation); the lab is as it was"
else
  die "forced resync did not restore ${SECRET}; run 'make configure'"
fi
exit 1
