#!/usr/bin/env bash
# scripts/verify-stack.sh — make verify: full stack health check.
# ✓ / ✗ / ⚠ rows; non-zero exit on any ✗.
# All URLs derived from the infra contract — no literal domains.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd oc jq curl

require_kubeconfig

INFRA_JSON="${BUILD_DIR}/terraform/infra.json"
[[ -f "${INFRA_JSON}" ]] || die ".build/terraform/infra.json not found — run 'make infra'"
APPS_DOMAIN="$(jq -r '.cluster.apps_domain' "${INFRA_JSON}")"
VAULT_ADDR="https://vault.${APPS_DOMAIN}"
SEAL_ADDR="https://vault-seal.${APPS_DOMAIN}"
VAULT_CA="${SECRETS_DIR}/tls/pub/ca.pem"
TOKEN_FILE="${SECRETS_DIR}/tokens/ansible-platform"

PASS=0 WARN=0 FAIL=0
row() {
  local sym="$1" label="$2" detail="$3"
  printf '  %s  %-55s %s\n' "${sym}" "${label}" "${detail}"
  case "${sym}" in
    ✓) PASS=$((PASS+1)) ;;
    ⚠) WARN=$((WARN+1)) ;;
    ✗) FAIL=$((FAIL+1)) ;;
  esac
}

check() {
  local label="$1" result="$2" detail="$3"
  if [[ "${result}" == "ok" ]]; then row "✓" "${label}" "${detail}"
  elif [[ "${result}" == "warn" ]]; then row "⚠" "${label}" "${detail}"
  else row "✗" "${label}" "${detail}"; fi
}

printf '\n\033[1m=== Shift Gear stack verify ===\033[0m\n\n'

# ── Cluster operators ─────────────────────────────────────────────────────────
degraded=$(oc get clusteroperators -o json 2>/dev/null | \
  jq '[.items[] | select(.status.conditions[]? | select(.type=="Degraded" and .status=="True"))] | length')
if [[ "${degraded}" -eq 0 ]]; then
  check "Cluster operators: none Degraded" ok "0 degraded"
else
  check "Cluster operators: ${degraded} Degraded" fail "${degraded} degraded"
fi

# ── Seal Vault ────────────────────────────────────────────────────────────────
seal_json=$(curl -sf --cacert "${VAULT_CA}" "${SEAL_ADDR}/v1/sys/health" 2>/dev/null || echo '{}')
seal_init=$(jq -r '.initialized // false' <<<"${seal_json}")
seal_sealed=$(jq -r '.sealed // true' <<<"${seal_json}")
if [[ "${seal_init}" == "true" && "${seal_sealed}" == "false" ]]; then
  check "Seal Vault: initialized and unsealed" ok "shamir"
else
  check "Seal Vault: initialized=${seal_init} sealed=${seal_sealed}" fail "check seal Vault"
fi

# ── Main Vault cluster ────────────────────────────────────────────────────────
if [[ -f "${TOKEN_FILE}" ]]; then
  VAULT_TOKEN="$(cat "${TOKEN_FILE}")"
  ha_json=$(curl -sf --cacert "${VAULT_CA}" \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H "X-Vault-Namespace: shift-gear" \
    "${VAULT_ADDR}/v1/sys/ha-status" 2>/dev/null || echo '{}')
  active=$(jq '[.nodes[]? | select(.active_node==true)] | length' <<<"${ha_json}")
  voters=$(jq '[.nodes[]? | select(.voter==true)] | length' <<<"${ha_json}")
  if [[ "${active}" -eq 1 && "${voters}" -eq 3 ]]; then
    check "Vault HA: 1 active, 3 voters" ok "transit seal"
  else
    check "Vault HA: active=${active} voters=${voters}" fail "expected 1 active, 3 voters"
  fi

  # Licence expiry
  lic_json=$(curl -sf --cacert "${VAULT_CA}" \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    "${VAULT_ADDR}/v1/sys/license/status" 2>/dev/null || echo '{}')
  expiry=$(jq -r '.data.expiration_time // ""' <<<"${lic_json}")
  if [[ -n "${expiry}" ]]; then
    now_ts=$(date +%s)
    exp_ts=$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "${expiry}" +%s 2>/dev/null || \
             date -d "${expiry}" +%s 2>/dev/null || echo 0)
    days_left=$(( (exp_ts - now_ts) / 86400 ))
    if [[ "${days_left}" -gt 30 ]]; then
      check "Vault licence: valid" ok "${days_left} days remaining"
    else
      check "Vault licence: expiring soon" warn "${days_left} days remaining"
    fi
  else
    check "Vault licence: could not read expiry" warn "check sys/license/status"
  fi
else
  check "Vault HA: token not found (skip)" warn "${TOKEN_FILE} missing"
fi

# ── Seal agent ────────────────────────────────────────────────────────────────
agent_ready=$(oc -n sg-vault-seal get deployment seal-agent \
  -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)
if [[ "${agent_ready}" -ge 1 ]]; then
  check "Seal agent: available" ok "${agent_ready}/1 ready"
else
  check "Seal agent: not available" fail "0/1 ready"
fi

# ── VSO CSV ───────────────────────────────────────────────────────────────────
csv_phase=$(oc -n openshift-operators get csv -l operators.coreos.com/vault-secrets-operator.openshift-operators='' \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "unknown")
if [[ "${csv_phase}" == "Succeeded" ]]; then
  check "VSO CSV: Succeeded" ok "${csv_phase}"
else
  check "VSO CSV: ${csv_phase}" fail "expected Succeeded"
fi

# ── VSO secrets synced ────────────────────────────────────────────────────────
for secret in app-config db-creds; do
  if oc -n sg-workloads get secret "${secret}" >/dev/null 2>&1; then
    check "VSO Secret: ${secret} in sg-workloads" ok "present"
  else
    check "VSO Secret: ${secret} in sg-workloads" fail "absent"
  fi
done

# ── Workload Deployments available ───────────────────────────────────────────
for d in sg-app/agent-demo sg-workloads/workload-a sg-workloads/workload-b sg-identity/openldap sg-identity/keycloak; do
  ns="${d%%/*}"; dep="${d##*/}"
  avail=$(oc -n "${ns}" get deployment "${dep}" \
    -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo 0)
  desired=$(oc -n "${ns}" get deployment "${dep}" \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 1)
  if [[ "${avail}" -ge "${desired}" ]]; then
    check "Deployment: ${dep} (${ns})" ok "${avail}/${desired} available"
  else
    check "Deployment: ${dep} (${ns})" fail "${avail}/${desired} available"
  fi
done

# ── Agent demo rendered its file ──────────────────────────────────────────────
demo_pod=$(oc -n sg-app get pod -l app.kubernetes.io/name=agent-demo \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "${demo_pod}" ]]; then
  if oc -n sg-app exec "${demo_pod}" -c app -- test -s /vault/secrets/demo-secret 2>/dev/null; then
    check "Agent demo: demo-secret rendered" ok "${demo_pod}"
  else
    check "Agent demo: demo-secret not rendered" fail "/vault/secrets/demo-secret empty or absent"
  fi
else
  check "Agent demo: pod not found" warn "agent-demo pod not running"
fi

# ── Gate files ────────────────────────────────────────────────────────────────
for gate in idempotency drift secret-scan validation; do
  gate_file="${BUILD_DIR}/gates/${gate}.json"
  if [[ -f "${gate_file}" ]]; then
    result=$(jq -r '.result // "unknown"' "${gate_file}" 2>/dev/null)
    if [[ "${result}" == "pass" ]]; then
      check "Gate: ${gate}" ok "${result}"
    else
      check "Gate: ${gate}" fail "${result}"
    fi
  else
    check "Gate: ${gate}" fail "${gate_file} not found"
  fi
done

# ── No workload pods have VAULT_* in their env ────────────────────────────────
vault_env_found=false
for ns in sg-workloads sg-app; do
  for pod in $(oc -n "${ns}" get pods -o name 2>/dev/null | sed 's|pod/||'); do
    if oc -n "${ns}" exec "${pod}" -- env 2>/dev/null | grep -qE '^VAULT_'; then
      check "No VAULT_* env in ${ns}/${pod}" fail "VAULT_* found — remove from pod spec"
      vault_env_found=true
    fi
  done
done
[[ "${vault_env_found}" == "false" ]] && check "No VAULT_* env in workload/app pods" ok "clean"

# ── Summary ───────────────────────────────────────────────────────────────────
printf '\n  %d ✓  %d ⚠  %d ✗\n\n' "${PASS}" "${WARN}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]] || die "verify-stack: ${FAIL} failure(s) — see ✗ rows above"
ok "verify-stack passed"
