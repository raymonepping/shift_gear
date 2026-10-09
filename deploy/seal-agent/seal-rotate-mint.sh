#!/bin/sh
# deploy/seal-agent/seal-rotate-mint.sh — rotator, step 1 (init container,
# Vault image). The Vault image has the vault CLI but no curl or jq, so this
# step does every Vault call with the CLI and hands its results to step 2
# through an in-memory volume (/work):
#   new-secret-id, new-accessor  — the freshly minted secret-id
#   old-accessors                — every other secret-id of the role
#   token                        — the rotator's own short-lived token
# Never prints a secret.
set -eu
umask 077
ROLE=sg-seal-autounseal
W=/work
export VAULT_ADDR VAULT_CACERT

VAULT_TOKEN="$(vault write -field=token auth/approle/login \
  role_id="$(cat /vault/approle/role-id)" secret_id="$(cat /vault/approle/secret-id)")"
export VAULT_TOKEN

vault write -format=json -f "auth/approle/role/${ROLE}/secret-id" \
  metadata='{"by":"sg-seal-rotator"}' >"${W}/minted.json"
sed -n 's/^ *"secret_id": "\([^"]*\)".*/\1/p' "${W}/minted.json" >"${W}/new-secret-id"
sed -n 's/^ *"secret_id_accessor": "\([^"]*\)".*/\1/p' "${W}/minted.json" >"${W}/new-accessor"
rm -f "${W}/minted.json"
if [ ! -s "${W}/new-secret-id" ] || [ ! -s "${W}/new-accessor" ]; then
  echo "seal-rotator: could not read the minted secret-id" >&2
  exit 1
fi

vault list -format=json "auth/approle/role/${ROLE}/secret-id" |
  sed -n 's/^ *"\([^"]*\)",*$/\1/p' | grep -vx "$(cat "${W}/new-accessor")" >"${W}/old-accessors" || true
printf '%s' "${VAULT_TOKEN}" >"${W}/token"
echo "$(date -u +%FT%TZ) seal-rotator: minted a secret-id (accessor $(cat "${W}/new-accessor"))"
