#!/usr/bin/env bash
# Shared reader for scripts/phases.txt. Source it; it defines phases <tool>,
# which prints the phase names of that tool (or all as "<tool> <name>").
PHASES_FILE="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/phases.txt"

phases() {
  local want="${1:-}" tool name
  while read -r tool name; do
    [[ -z "${tool}" || "${tool}" == \#* ]] && continue
    if [[ -z "${want}" ]]; then
      printf '%s %s\n' "${tool}" "${name}"
    elif [[ "${tool}" == "${want}" ]]; then
      printf '%s\n' "${name}"
    fi
  done <"${PHASES_FILE}"
}
