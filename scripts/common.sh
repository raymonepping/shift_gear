#!/usr/bin/env bash
# Shared helpers. Paths only — never credentials.

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_DIR="${ROOT_DIR}/.secrets"
CACHE_DIR="${ROOT_DIR}/.cache"
BUILD_DIR="${ROOT_DIR}/.build"
TF_DIR="${ROOT_DIR}/terraform"
export ROOT_DIR SECRETS_DIR CACHE_DIR BUILD_DIR TF_DIR
if [[ -s "${SECRETS_DIR}/kube/config" ]]; then export KUBECONFIG="${SECRETS_DIR}/kube/config"; fi

# Tools linked by the substrate scripts (e.g. the cluster CLI) come first.
export PATH="${CACHE_DIR}/bin:${PATH}"

info()  { printf '\033[1m==>\033[0m %s\n' "$*" >&2; }
ok()    { printf '\033[32m ok\033[0m %s\n' "$*" >&2; }
warn()  { printf '\033[33mWARN\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
log()   { printf '==> %s\n' "$*" >&2; }

sg_lock() {
  if [[ -n "${SG_LOCK_FD:-}" ]] && python3 "${ROOT_DIR}/scripts/with-lock.py" --check; then return; fi
  exec python3 "${ROOT_DIR}/scripts/with-lock.py" "${BASH}" "${BASH_SOURCE[1]}" "$@"
}

# Standalone gates may extend the current attempt only on its actual cluster.
# The full verifier separately checks the attempt's source digest.
sg_gate_context() {
  [[ -n "${SG_RUN_ID:-}" && -n "${SG_CLUSTER_ID:-}" ]] && return 0
  [[ -s "${BUILD_DIR}/run.json" ]] || return 0
  local actual candidate run
  actual="$(oc --request-timeout=5s get namespace kube-system -o jsonpath='{.metadata.uid}' 2>/dev/null)" || return 0
  candidate="$(jq -r '.clusterId // empty' "${BUILD_DIR}/run.json")"
  run="$(jq -r '.runId // empty' "${BUILD_DIR}/run.json")"
  [[ -n "${actual}" && "${actual}" == "${candidate}" && -n "${run}" ]] || return 0
  export SG_RUN_ID="${run}" SG_CLUSTER_ID="${actual}"
}

require_cmd() {
  local c
  for c in "$@"; do command -v "${c}" >/dev/null 2>&1 || die "Required command not found: ${c}"; done
}

require_kubeconfig() {
  [[ -s "${ROOT_DIR}/.secrets/kube/config" ]] || die ".secrets/kube/config not found — run 'make crc-up' first"
  export KUBECONFIG="${ROOT_DIR}/.secrets/kube/config"
}

prepare_local_dirs() {
  umask 077
  mkdir -p "${SECRETS_DIR}" "${CACHE_DIR}/ansible/tmp" "${CACHE_DIR}/ansible/collections" \
    "${CACHE_DIR}/ansible/inventory" "${BUILD_DIR}/ansible-stats" "${BUILD_DIR}/gates"
  chmod 700 "${SECRETS_DIR}" "${CACHE_DIR}" "${BUILD_DIR}"
}
