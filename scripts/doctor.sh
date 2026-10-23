#!/usr/bin/env bash
# Independent host/API/seal states. No startup, stop, token or credential output.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
require_kubeconfig
"${SCRIPT_DIR}/crc-health.sh"
oc --request-timeout=5s get namespace kube-system -o jsonpath='Cluster identity: {.metadata.uid}{"\n"}'
for item in sg-vault-seal/vault-seal-0 sg-vault/vault-0 sg-vault/vault-1 sg-vault/vault-2; do
  namespace="${item%/*}" pod="${item#*/}"
  address=https://127.0.0.1:8200
  [[ "${namespace}" == sg-vault-seal ]] && address=https://vault-seal.sg-vault-seal.svc:8200
  if json="$(oc --request-timeout=5s -n "${namespace}" exec "${pod}" -- env "VAULT_ADDR=${address}" vault status -format=json 2>/dev/null)"; then :; fi
  if jq -e 'has("sealed")' >/dev/null 2>&1 <<<"${json:-}"; then
    jq -n --arg pod "${pod}" --argjson status "${json}" '{pod:$pod,initialized:$status.initialized,sealed:$status.sealed,version:$status.version}'
  else
    printf '%s: unavailable (API reachability does not imply Vault readiness)\n' "${pod}"
  fi
done
for file in "${SECRETS_DIR}/tls/pub/"*.crt "${SECRETS_DIR}/tls/pub/ca.pem"; do
  [[ -f "${file}" ]] || continue
  printf '%s: ' "${file##*/}"
  openssl x509 -in "${file}" -noout -enddate
done
