#!/usr/bin/env bash
# scripts/ui-test.sh — make ui-test: Playwright journeys + axe WCAG 2.1 AA
# against the running console (https://shiftgear.<apps_domain>).
# The five people's passwords are read from Vault KV with Ansible's own token
# into this process's environment only (SG_PW_<USER>); never written to disk,
# never printed. Extra arguments go to playwright (e.g. --project chromium).
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
require_cmd jq
require_cmd curl
require_cmd npx

apps_domain="$(jq -r '.cluster.apps_domain // empty' "${BUILD_DIR}/terraform/infra.json" 2>/dev/null || true)"
[[ -n "${apps_domain}" ]] || die "No apps_domain in .build/terraform/infra.json — run 'make infra'"
token_file="${SECRETS_DIR}/tokens/ansible-platform"
[[ -s "${token_file}" ]] || die "Missing ${token_file#"${ROOT_DIR}"/} — run 'make bootstrap'"

identity="$(curl -fsS --cacert "${SECRETS_DIR}/tls/pub/ca.pem" \
  -H "X-Vault-Token: $(<"${token_file}")" -H "X-Vault-Namespace: shift-gear" \
  "https://vault.${apps_domain}/v1/kv/data/shift-gear/identity")" || die "Cannot read the identity secrets from Vault"
for u in ada ben cleo dirk finn; do
  value="$(jq -r --arg k "user_${u}" '.data.data[$k] // empty' <<<"${identity}")"
  [[ -n "${value}" ]] || die "No password for ${u} in Vault — run 'make identity'"
  export "SG_PW_${u^^}=${value}"
done
unset identity value

export SG_UI_URL="https://shiftgear.${apps_domain}"
cd "${ROOT_DIR}/ui"
exec npx playwright test "$@"
