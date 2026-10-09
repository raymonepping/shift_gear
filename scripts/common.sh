#!/usr/bin/env bash
# Shared helpers. Paths only — never credentials.

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_DIR="${ROOT_DIR}/.secrets"
CACHE_DIR="${ROOT_DIR}/.cache"
BUILD_DIR="${ROOT_DIR}/.build"
TF_DIR="${ROOT_DIR}/terraform"
export ROOT_DIR SECRETS_DIR CACHE_DIR BUILD_DIR TF_DIR

# Tools linked by the substrate scripts (e.g. the cluster CLI) come first.
export PATH="${CACHE_DIR}/bin:${PATH}"

info()  { printf '\033[1m==>\033[0m %s\n' "$*" >&2; }
ok()    { printf '\033[32m ok\033[0m %s\n' "$*" >&2; }
warn()  { printf '\033[33mWARN\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
log()   { printf '==> %s\n' "$*" >&2; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

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
