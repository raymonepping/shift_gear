#!/usr/bin/env bash
# scripts/drift.sh — Read-only: terraform plan -detailed-exitcode on every
# Terraform root and --check --diff on every Ansible phase. One table.
#   TF_ONLY=1   Terraform plans only
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=phases.sh
source "${SCRIPT_DIR}/phases.sh"
require_cmd jq

rows=()
fails=0

while read -r tool name; do
  if [[ "${tool}" == "tf" ]]; then
    set +e
    "${SCRIPT_DIR}/tf-run.sh" "${name}" plan -detailed-exitcode -no-color \
      >"${CACHE_DIR}/drift-${name}.log" 2>&1 </dev/null
    rc=$?
    set -e
    case "${rc}" in
      0) rows+=("${name}|terraform|clean|plan empty") ;;
      2)
        summary="$(grep -E '^Plan:' "${CACHE_DIR}/drift-${name}.log" | head -1)"
        rows+=("${name}|terraform|DRIFT|${summary:-plan not empty}")
        fails=$((fails + 1))
        ;;
      *)
        rows+=("${name}|terraform|ERROR|see .cache/drift-${name}.log")
        fails=$((fails + 1))
        ;;
    esac
  elif [[ "${TF_ONLY:-0}" != "1" ]]; then
    if CHECK=1 "${SCRIPT_DIR}/ansible-run.sh" "${name}" >"${CACHE_DIR}/drift-${name}.log" 2>&1; then
      changed="$(jq -r '.changed_total' "${BUILD_DIR}/ansible-stats/${name}.check.json" 2>/dev/null || echo '?')"
      if [[ "${changed}" == "0" ]]; then
        rows+=("${name}|ansible|clean|check mode changed=0")
      else
        hosts="$(jq -r '[.hosts | to_entries[] | select(.value.changed > 0) | "\(.key)=\(.value.changed)"] | join(" ")' \
          "${BUILD_DIR}/ansible-stats/${name}.check.json" 2>/dev/null || echo '')"
        rows+=("${name}|ansible|DRIFT|would change: ${hosts}")
        fails=$((fails + 1))
      fi
    else
      rows+=("${name}|ansible|ERROR|see .cache/drift-${name}.log")
      fails=$((fails + 1))
    fi
  fi
done < <(phases)

printf '\n%-14s %-10s %-7s %s\n' LAYER TOOL RESULT DETAIL
for row in "${rows[@]}"; do
  IFS='|' read -r l t r d <<<"${row}"
  printf '%-14s %-10s %-7s %s\n' "${l}" "${t}" "${r}" "${d}"
done

mkdir -p "${BUILD_DIR}/gates"
jq -n \
  --arg result "$([[ ${fails} -eq 0 ]] && echo pass || echo fail)" \
  --arg scope "$([[ "${TF_ONLY:-0}" == "1" ]] && echo terraform || echo all)" \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{gate: "drift", scope: $scope, result: $result, at: $at}' \
  >"${BUILD_DIR}/gates/drift.json"

[[ ${fails} -eq 0 ]] || die "${fails} layer(s) drifted."
info "No drift"
