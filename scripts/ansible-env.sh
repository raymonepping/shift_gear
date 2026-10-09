#!/usr/bin/env bash
# scripts/ansible-env.sh — Export the controller environment for ansible-playbook.
#
# Reads ONLY the allow-listed keys from the ignored root .env. The file is
# parsed line by line — never sourced or evaluated — and values are never
# printed. Values already present in the caller's environment win.
#
# RHSM_* keys in .env are ignored on purpose: there is no RHEL host to register
# in Shift Gear. CRC pulls Red Hat images with the pull secret; in-cluster
# builds use UBI images, which need no subscription. (00_01_shift_gear.md §3)
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

ENV_FILE="${SG_ENV_FILE:-${ROOT_DIR}/.env}"
# RHSM_* keys are present in .env but intentionally not allowed here.
ALLOWED_KEYS=(VAULT_LICENSE)

load_env_file() {
  local line key value allowed
  [[ -f "${ENV_FILE}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "${line}" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Z_][A-Z0-9_]*)=(.*)$ ]] || continue
    key="${BASH_REMATCH[2]}"
    value="${BASH_REMATCH[3]}"
    for allowed in "${ALLOWED_KEYS[@]}"; do
      [[ "${key}" == "${allowed}" ]] || continue
      # Strip one pair of surrounding quotes, if present.
      if [[ "${value}" =~ ^\"(.*)\"$ || "${value}" =~ ^\'(.*)\'$ ]]; then
        value="${BASH_REMATCH[1]}"
      fi
      if [[ -z "${!key:-}" ]]; then
        export "${key}=${value}"
      fi
    done
  done <"${ENV_FILE}"
}

prepare_local_dirs
load_env_file

export ANSIBLE_CONFIG="${ROOT_DIR}/ansible.cfg"
export ANSIBLE_LOCAL_TEMP="${CACHE_DIR}/ansible/tmp"
export ANSIBLE_COLLECTIONS_PATH="${CACHE_DIR}/ansible/collections"
export ANSIBLE_GALAXY_TOKEN_PATH="${CACHE_DIR}/ansible/galaxy_token"
export ANSIBLE_ROLES_PATH="${ROOT_DIR}/ansible/roles"
export ANSIBLE_CALLBACK_PLUGINS="${ROOT_DIR}/ansible/plugins/callback"
# sg_stats writes the recap counts of a phase here (SG_PHASE set by ansible-run.sh).
export SG_STATS_DIR="${BUILD_DIR}/ansible-stats"

export KUBECONFIG="${ROOT_DIR}/.secrets/kube/config"
