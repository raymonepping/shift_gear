#!/bin/sh
# deploy/seal-agent/seal-rotate.sh — rotator, step 2 (OpenShift cli image:
# oc + curl). Order as in golden_ticket: the agent gets the new secret-id
# first (patch its Secret), and only then are the old ones destroyed — a
# failed patch never leaves the agent without a valid secret-id.
# Never prints a secret.
set -eu
W=/work
ROLE=sg-seal-autounseal
token="$(cat "${W}/token")"

# printf %s: the value without the trailing newline sed wrote.
encoded="$(printf '%s' "$(cat "${W}/new-secret-id")" | base64 | tr -d '\n')"
# In-cluster: oc uses the pod's ServiceAccount (get/patch on this one Secret).
oc patch secret seal-agent-approle --type=json \
  -p "[{\"op\":\"replace\",\"path\":\"/data/secret-id\",\"value\":\"${encoded}\"}]" >/dev/null

destroyed=0
while read -r accessor; do
  [ -n "${accessor}" ] || continue
  curl -fsS --cacert "${VAULT_CACERT}" -H "X-Vault-Token: ${token}" -X POST \
    --data "{\"secret_id_accessor\":\"${accessor}\"}" \
    "${VAULT_ADDR}/v1/auth/approle/role/${ROLE}/secret-id-accessor/destroy" >/dev/null
  destroyed=$((destroyed + 1))
done <"${W}/old-accessors"

curl -fsS --cacert "${VAULT_CACERT}" -H "X-Vault-Token: ${token}" -X POST \
  "${VAULT_ADDR}/v1/auth/token/revoke-self" >/dev/null 2>&1 || true
rm -f "${W}/token" "${W}/new-secret-id"
echo "$(date -u +%FT%TZ) seal-rotator: rotated (new accessor $(cat "${W}/new-accessor"), destroyed ${destroyed})"
