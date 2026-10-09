#!/usr/bin/env bash
# scripts/vso-status.sh
# Show VSO resource sync status and workload pod states in sg-workloads.
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

require_kubeconfig
KC="KUBECONFIG=${ROOT_DIR}/.secrets/kube/config"

echo "=== VaultConnection ==="
eval "${KC}" oc -n sg-workloads get vaultconnection default \
  -o custom-columns='NAME:.metadata.name,VALID:.status.valid,MSG:.status.conditions[0].message' 2>/dev/null || echo "  (not found)"

echo ""
echo "=== VaultAuth ==="
eval "${KC}" oc -n sg-workloads get vaultauth default \
  -o custom-columns='NAME:.metadata.name,VALID:.status.valid,MSG:.status.conditions[0].message' 2>/dev/null || echo "  (not found)"

echo ""
echo "=== VaultStaticSecret ==="
eval "${KC}" oc -n sg-workloads get vaultstaticsecret app-config \
  -o custom-columns='NAME:.metadata.name,SYNCED:.status.secretMAC,LAST:.status.lastGeneration' 2>/dev/null || echo "  (not found)"

echo ""
echo "=== VaultDynamicSecret ==="
eval "${KC}" oc -n sg-workloads get vaultdynamicsecret db-creds \
  -o custom-columns='NAME:.metadata.name,EXPIRE:.status.secretLease.renewable,LAST:.status.lastRenewalTime' 2>/dev/null || echo "  (not found)"

echo ""
echo "=== Workload pods ==="
eval "${KC}" oc -n sg-workloads get pods \
  -l 'app.kubernetes.io/part-of=shift-gear' \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,READY:.status.conditions[?(@.type=="Ready")].status'

echo ""
echo "=== app-config Secret ==="
eval "${KC}" oc -n sg-workloads get secret app-config \
  -o custom-columns='NAME:.metadata.name,KEYS:.data' 2>/dev/null | head -5 || echo "  (not found yet)"

echo ""
echo "=== db-creds Secret ==="
eval "${KC}" oc -n sg-workloads get secret db-creds \
  -o jsonpath='{.metadata.name}: lease_duration={.metadata.annotations.secrets\.hashicorp\.com/vaultDynamicSecretLease}{"\n"}' 2>/dev/null || echo "  (not found yet)"
