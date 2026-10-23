#!/usr/bin/env bash
# Isolate CRC's login/logout side effects from the project kubeconfig.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
require_cmd crc
umask 077
mkdir -p "${CACHE_DIR}"
chmod 700 "${CACHE_DIR}"
control_kubeconfig="$(mktemp "${CACHE_DIR}/crc-control.XXXXXX")"
trap 'rm -f "${control_kubeconfig}"' EXIT
if [[ -s "${KUBECONFIG:-}" ]]; then
  cp "${KUBECONFIG}" "${control_kubeconfig}"
else
  printf 'apiVersion: v1\nkind: Config\nclusters: []\ncontexts: []\nusers: []\ncurrent-context: ""\n' >"${control_kubeconfig}"
fi
KUBECONFIG="${control_kubeconfig}" crc "$@"
