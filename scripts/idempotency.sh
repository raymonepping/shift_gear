#!/usr/bin/env bash
# scripts/idempotency.sh — Re-run every Ansible phase; each must report
# changed=0 on every host (exceptions only from idempotency-allow.txt,
# each with a documented reason). Counts come from the sg_stats callback.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=phases.sh
source "${SCRIPT_DIR}/phases.sh"
require_cmd jq

allowed() { grep -Eq "^$1[[:space:]]" "${SCRIPT_DIR}/idempotency-allow.txt"; }
stats="${BUILD_DIR}/ansible-stats"
fails=0
rows=()

while read -r phase; do
  printf '\n\033[1m== idempotency: %s\033[0m\n' "${phase}" >&2
  if ! "${SCRIPT_DIR}/ansible-run.sh" "${phase}" >"${CACHE_DIR}/idempotency-${phase}.log" 2>&1; then
    rows+=("${phase}|FAILED|see .cache/idempotency-${phase}.log")
    fails=$((fails + 1))
    continue
  fi
  stats_file="${stats}/${phase}.json"
  if [[ ! -f "${stats_file}" ]]; then
    rows+=("${phase}|NO_STATS|sg_stats callback did not write ${stats_file}")
    fails=$((fails + 1))
    continue
  fi
  changed="$(jq -r '.changed_total' "${stats_file}")"
  hosts="$(jq -r '[.hosts | to_entries[] | select(.value.changed > 0) | "\(.key)=\(.value.changed)"] | join(" ")' "${stats_file}")"
  if [[ "${changed}" == "0" ]]; then
    rows+=("${phase}|changed=0|")
  elif allowed "${phase}"; then
    rows+=("${phase}|changed=${changed} (allowed)|${hosts}")
  else
    rows+=("${phase}|changed=${changed}|${hosts}")
    fails=$((fails + 1))
  fi
done < <(phases ansible)

printf '\n%-14s %-26s %s\n' PHASE RESULT DETAIL
for row in "${rows[@]}"; do
  IFS='|' read -r p r d <<<"${row}"
  printf '%-14s %-26s %s\n' "${p}" "${r}" "${d}"
done

mkdir -p "${BUILD_DIR}/gates"
jq -n \
  --arg result "$([[ ${fails} -eq 0 ]] && echo pass || echo fail)" \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{gate: "idempotency", result: $result, at: $at}' \
  >"${BUILD_DIR}/gates/idempotency.json"

[[ ${fails} -eq 0 ]] || die "${fails} phase(s) are not idempotent."
info "Idempotency: every Ansible phase changed=0"
