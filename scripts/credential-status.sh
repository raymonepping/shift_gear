#!/usr/bin/env bash
# Metadata only. Missing/refused sources fail, never print HTTP response bodies.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
domain="$(jq -er .cluster.apps_domain "${BUILD_DIR}/terraform/infra.json")"
for name in tf-seal ansible-seal tf-platform ansible-platform; do
  host=vault
  [[ "${name}" == *-seal ]] && host=vault-seal
  data="$(curl -fsS --max-time 10 --cacert "${SECRETS_DIR}/tls/pub/ca.pem" -H "X-Vault-Token: $(cat "${SECRETS_DIR}/tokens/${name}")" "https://${host}.${domain}/v1/auth/token/lookup-self")" || die "Credential metadata unavailable: ${name}"
  jq --arg name "${name}" '{name:$name,ttl:.data.ttl,expire_time:.data.expire_time,renewable:.data.renewable,policies:.data.policies}' <<<"${data}"
done
python3 "${SCRIPT_DIR}/state-audit.py"
