#!/usr/bin/env bash
# scripts/vso-status.sh
# Show VSO resource sync status and workload pod states in sg-workloads.
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

require_kubeconfig

echo "=== VaultConnection ==="
oc -n sg-workloads get vaultconnection default \
  -o custom-columns='NAME:.metadata.name,VALID:.status.valid,MSG:.status.conditions[0].message' 2>/dev/null || echo "  (not found)"

echo ""
echo "=== VaultAuth ==="
oc -n sg-workloads get vaultauth default \
  -o custom-columns='NAME:.metadata.name,VALID:.status.valid,MSG:.status.conditions[0].message' 2>/dev/null || echo "  (not found)"

echo ""
echo "=== VaultStaticSecret ==="
oc -n sg-workloads get vaultstaticsecret app-config \
  -o custom-columns='NAME:.metadata.name,SYNCED:.status.conditions[?(@.type=="SecretSynced")].status,GENERATION:.status.lastGeneration' 2>/dev/null || echo "  (not found)"

echo ""
echo "=== VaultDynamicSecret ==="
oc -n sg-workloads get vaultdynamicsecret db-creds \
  -o custom-columns='NAME:.metadata.name,RENEWABLE:.status.secretLease.renewable,DURATION:.status.secretLease.duration,LAST_RENEWAL:.status.lastRenewalTime' 2>/dev/null || echo "  (not found)"

echo ""
echo "=== Workload pods ==="
oc -n sg-workloads get pods \
  -l 'app.kubernetes.io/part-of=shift-gear' \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,READY:.status.conditions[?(@.type=="Ready")].status'

echo ""
echo "=== app-config Secret ==="
oc -n sg-workloads get secret app-config -o json 2>/dev/null | \
  jq -r '"\(.metadata.name): keys=\(.data | keys | join(","))"' || echo "  (not found yet)"

echo ""
echo "=== db-creds Secret ==="
oc -n sg-workloads get secret db-creds -o json 2>/dev/null | \
  jq -r '"\(.metadata.name): keys=\(.data | keys | join(","))"' || echo "  (not found yet)"
