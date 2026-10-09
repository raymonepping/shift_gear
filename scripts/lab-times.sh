#!/usr/bin/env bash
# scripts/lab-times.sh — print the timing table from the last convergence.json.
# Reads .build/convergence.json; runs nothing. Used by make lab-times.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=phases.sh
source "${SCRIPT_DIR}/phases.sh"
require_cmd jq

conv="${BUILD_DIR}/convergence.json"
if [[ ! -f "${conv}" ]]; then
  die "No convergence.json found — run make lab first."
fi

# fmt_duration <seconds> → "NmNNs"
fmt_duration() {
  local s=$1
  printf '%dm%02ds' "$((s / 60))" "$((s % 60))"
}

printf '\033[1m%-16s %-12s %s\033[0m\n' "phase" "tool" "time"

while read -r tool name; do
  secs="$(jq -r --arg p "${name}" '.phase_seconds[$p] // empty' "${conv}")"
  if [[ -z "${secs}" ]]; then
    printf '%-16s %-12s %s\n' "${name}" \
      "$([[ "${tool}" == "tf" ]] && echo "terraform" || echo "ansible")" "—"
  else
    printf '%-16s %-12s %s\n' "${name}" \
      "$([[ "${tool}" == "tf" ]] && echo "terraform" || echo "ansible")" \
      "$(fmt_duration "${secs}")"
  fi
done < <(phases)

for gate in idempotency drift secret-scan; do
  secs="$(jq -r --arg g "${gate}" '.gate_seconds[$g] // empty' "${conv}")"
  if [[ -z "${secs}" ]]; then
    printf '%-16s %-12s %s\n' "${gate}" "gate" "—"
  else
    printf '%-16s %-12s %s\n' "${gate}" "gate" "$(fmt_duration "${secs}")"
  fi
done

total="$(jq -r '.total_seconds // empty' "${conv}")"
if [[ -z "${total}" ]]; then
  printf '%-16s %-12s %s\n' "total" "" "—"
else
  printf '%-16s %-12s %s\n' "total" "" "$(fmt_duration "${total}")"
fi
