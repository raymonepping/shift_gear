#!/usr/bin/env bash
# scripts/wl-a-rotate.sh
# Write a new version of the app-config KV path via sg-ansible-platform.
# The VaultStaticSecret refreshAfter=30s picks up the new version and
# triggers a rollout of workload-a within ~30 seconds.
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

INFRA_JSON="${ROOT_DIR}/.build/terraform/infra.json"
if [[ ! -f "$INFRA_JSON" ]]; then
  die "ERROR: $INFRA_JSON not found — run 'make infra' first."
fi

APPS_DOMAIN=$(jq -r '.cluster.apps_domain' "$INFRA_JSON")
VAULT_ADDR="https://vault.${APPS_DOMAIN}"
VAULT_CACERT="${ROOT_DIR}/.secrets/tls/pub/ca.pem"
TOKEN_FILE="${ROOT_DIR}/.secrets/tokens/ansible-platform"

if [[ ! -f "$TOKEN_FILE" ]]; then
  die "ERROR: ${TOKEN_FILE} not found — run 'make bootstrap' first."
fi

VAULT_TOKEN=$(cat "$TOKEN_FILE")
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

log "Writing new app-config version at ${TIMESTAMP}"

VAULT_ADDR="$VAULT_ADDR" \
VAULT_CACERT="$VAULT_CACERT" \
VAULT_TOKEN="$VAULT_TOKEN" \
VAULT_NAMESPACE="shift-gear" \
vault kv patch \
  -mount="shift-gear/kv" \
  "shift-gear/config/app-config" \
  rotated_at="${TIMESTAMP}"

ok "app-config updated — VSO will sync within ~30 s and workload-a will roll"
