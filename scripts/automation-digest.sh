#!/usr/bin/env bash
# scripts/automation-digest.sh — SHA-256 over sorted relative paths + contents
# of ansible/**/*.{yml,yaml,j2}, policies/**/*.hcl, terraform/**/*.tf,
# deploy/**, ansible.cfg and scripts/phases.txt.
# Used by lab.sh to stamp convergence; UI compares against stored stamp.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Collect files in sorted order — each find command is separate to avoid
# redirect collisions (ShellCheck SC2261)
{
  find "${ROOT_DIR}/ansible" -type f \( -name '*.yml' -o -name '*.yaml' -o -name '*.j2' \)
  find "${ROOT_DIR}/policies" -type f -name '*.hcl' 2>/dev/null || true
  find "${ROOT_DIR}/terraform" -type f -name '*.tf' 2>/dev/null || true
  find "${ROOT_DIR}/deploy" -type f 2>/dev/null || true
  [[ -f "${ROOT_DIR}/ansible.cfg" ]] && echo "${ROOT_DIR}/ansible.cfg" || true
  [[ -f "${ROOT_DIR}/scripts/phases.txt" ]] && echo "${ROOT_DIR}/scripts/phases.txt" || true
} | sort -u | xargs shasum -a 256 2>/dev/null | shasum -a 256 | cut -d' ' -f1
