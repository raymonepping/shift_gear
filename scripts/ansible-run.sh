#!/usr/bin/env bash
# scripts/ansible-run.sh — Run one named Shift Gear playbook with the project environment.
#
#   scripts/ansible-run.sh <playbook> [extra ansible-playbook args...]
#
# TAGS / SKIP_TAGS / CHECK=1 / LIMIT are honoured from the environment.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ansible-env.sh
source "${SCRIPT_DIR}/ansible-env.sh"

require_cmd ansible-playbook

playbook="${1:?usage: ansible-run.sh <playbook> [args...]}"
shift
playbook_path="${ROOT_DIR}/ansible/${playbook%.yml}.yml"
[[ -f "${playbook_path}" ]] || die "Unknown playbook: ${playbook} (looked for ${playbook_path})"

args=()
[[ -n "${TAGS:-}" ]]      && args+=(--tags "${TAGS}")
[[ -n "${SKIP_TAGS:-}" ]] && args+=(--skip-tags "${SKIP_TAGS}")
[[ -n "${LIMIT:-}" ]]     && args+=(--limit "${LIMIT}")
[[ "${CHECK:-0}" == "1" ]] && args+=(--check --diff)

export SG_PHASE="${playbook%.yml}"

# Ansible refuses non-blocking stdin; give it a plain one unless interactive.
cd "${ROOT_DIR}"
if [[ -t 0 ]]; then
  exec ansible-playbook "${playbook_path}" ${args[@]+"${args[@]}"} "$@"
else
  exec ansible-playbook "${playbook_path}" ${args[@]+"${args[@]}"} "$@" </dev/null
fi
