#!/usr/bin/env bash
# scripts/identity-show-user.sh
# Print one person's password from Vault KV.
# Usage: make identity-show-user PERSON=ada
# Lab-only: requires sg-ansible-platform token and direct Vault access.
set -euo pipefail

PERSON="${1:-}"
if [[ -z "$PERSON" ]]; then
  echo "Usage: make identity-show-user PERSON=<uid>" >&2
  echo "  Known users: ada  ben  cleo  dirk  finn" >&2
  exit 1
fi

# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

INFRA_JSON=".build/terraform/infra.json"
if [[ ! -f "$INFRA_JSON" ]]; then
  echo "ERROR: $INFRA_JSON not found — run 'make infra' first." >&2
  exit 1
fi

APPS_DOMAIN=$(jq -r '.cluster.apps_domain' "$INFRA_JSON")
VAULT_ADDR="https://vault.${APPS_DOMAIN}"
VAULT_CACERT=".secrets/tls/pub/ca.pem"
TOKEN_FILE=".secrets/tokens/ansible-platform"

if [[ ! -f "$TOKEN_FILE" ]]; then
  echo "ERROR: $TOKEN_FILE not found — run 'make bootstrap' first." >&2
  exit 1
fi

VAULT_TOKEN=$(cat "$TOKEN_FILE")

password=$(VAULT_ADDR="$VAULT_ADDR" \
           VAULT_CACERT="$VAULT_CACERT" \
           VAULT_TOKEN="$VAULT_TOKEN" \
           VAULT_NAMESPACE="shift-gear" \
           vault kv get -field "user_${PERSON}" \
             -mount="kv" "shift-gear/identity" 2>/dev/null || true)

if [[ -z "$password" ]]; then
  echo "ERROR: no password found for user '${PERSON}'" >&2
  echo "  Known users: ada  ben  cleo  dirk  finn" >&2
  exit 1
fi

echo "$password"
