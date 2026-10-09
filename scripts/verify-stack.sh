#!/usr/bin/env bash
# scripts/verify-stack.sh — make verify: full stack health check.
# ✓ / ✗ / ⚠ rows; non-zero exit on any ✗.
# Read-only: changes nothing in the cluster or in Vault. Never prints a token.
# Fails closed: a check that cannot run (missing file, unreachable API, empty
# answer) is ✗, never ✓.
# All URLs derived from the infra contract — no literal domains.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd oc
require_cmd jq
require_cmd curl
require_kubeconfig

INFRA_JSON="${BUILD_DIR}/terraform/infra.json"
[[ -f "${INFRA_JSON}" ]] || die ".build/terraform/infra.json not found — run 'make infra'"
APPS_DOMAIN="$(jq -r '.cluster.apps_domain // empty' "${INFRA_JSON}")"
[[ -n "${APPS_DOMAIN}" ]] || die "No apps_domain in .build/terraform/infra.json — run 'make infra'"
VAULT_ADDR="https://vault.${APPS_DOMAIN}"
SEAL_ADDR="https://vault-seal.${APPS_DOMAIN}"
VAULT_CA="${SECRETS_DIR}/tls/pub/ca.pem"
TOKEN_FILE="${SECRETS_DIR}/tokens/ansible-platform"

PASS=0 WARN=0 FAIL=0
row() {
  local sym="$1" label="$2" detail="$3"
  printf '  %s  %-55s %s\n' "${sym}" "${label}" "${detail}"
  case "${sym}" in
    ✓) PASS=$((PASS + 1)) ;;
    ⚠) WARN=$((WARN + 1)) ;;
    ✗) FAIL=$((FAIL + 1)) ;;
  esac
}

check() {
  local label="$1" result="$2" detail="$3"
  if [[ "${result}" == "ok" ]]; then row "✓" "${label}" "${detail}"
  elif [[ "${result}" == "warn" ]]; then row "⚠" "${label}" "${detail}"
  else row "✗" "${label}" "${detail}"; fi
}

# GET a root-namespace Vault endpoint with the ansible-platform token; prints
# the JSON body, or nothing on any failure.
vault_get() {
  curl -sf --max-time 10 --cacert "${VAULT_CA}" \
    -H "X-Vault-Token: $(<"${TOKEN_FILE}")" "${VAULT_ADDR}/v1/$1" 2>/dev/null || true
}

printf '\n\033[1m=== Shift Gear stack verify ===\033[0m\n\n'

# ── Cluster operators ─────────────────────────────────────────────────────────
co_json="$(oc get clusteroperators -o json 2>/dev/null || true)"
if [[ -z "${co_json}" ]]; then
  check "Cluster operators" fail "cannot list clusteroperators"
else
  degraded="$(jq '[.items[] | select(.status.conditions[]? | select(.type=="Degraded" and .status=="True"))] | length' <<<"${co_json}")"
  if [[ "${degraded}" -eq 0 ]]; then check "Cluster operators: none Degraded" ok "0 degraded"
  else check "Cluster operators: ${degraded} Degraded" fail "oc get co"; fi
fi

# ── Seal Vault ────────────────────────────────────────────────────────────────
seal_json="$(curl -s --max-time 10 --cacert "${VAULT_CA}" "${SEAL_ADDR}/v1/sys/health" 2>/dev/null || true)"
if [[ "$(jq -r '.initialized == true and .sealed == false' <<<"${seal_json:-null}" 2>/dev/null)" == "true" ]]; then
  check "Seal Vault: initialized and unsealed" ok "$(jq -r '.version' <<<"${seal_json}")"
else
  check "Seal Vault: initialized and unsealed" fail "unreachable, sealed or not initialised"
fi

# ── Main Vault cluster (root endpoints, no namespace header) ──────────────────
if [[ ! -s "${TOKEN_FILE}" ]]; then
  check "Vault cluster checks" fail "${TOKEN_FILE#"${ROOT_DIR}"/} missing — run 'make bootstrap'"
else
  ha_json="$(vault_get sys/ha-status)"
  raft_json="$(vault_get sys/storage/raft/configuration)"
  active="$(jq '[.nodes[]? | select(.active_node == true)] | length' <<<"${ha_json:-null}")"
  voters="$(jq '[.data.config.servers[]? | select(.voter == true)] | length' <<<"${raft_json:-null}")"
  if [[ "${active}" -eq 1 && "${voters}" -eq 3 ]]; then
    check "Vault HA: 1 active, 3 Raft voters" ok "transit seal through the seal agent"
  else
    check "Vault HA: 1 active, 3 Raft voters" fail "active=${active} voters=${voters}"
  fi

  lic_json="$(vault_get sys/license/status)"
  expiry="$(jq -r '.data.autoloaded.expiration_time // .data.expiration_time // empty' <<<"${lic_json:-null}")"
  if [[ -z "${expiry}" ]]; then
    check "Vault licence" fail "cannot read sys/license/status"
  else
    exp_ts="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "${expiry%%.*}" +%s 2>/dev/null ||
      date -u -d "${expiry}" +%s 2>/dev/null || echo 0)"
    days_left=$(((exp_ts - $(date +%s)) / 86400))
    if [[ "${days_left}" -gt 30 ]]; then check "Vault licence: valid" ok "${days_left} days remaining"
    elif [[ "${days_left}" -gt 0 ]]; then check "Vault licence: expiring soon" warn "${days_left} days remaining"
    else check "Vault licence" fail "expired or unreadable (${expiry})"; fi
  fi
fi

# ── Seal agent ────────────────────────────────────────────────────────────────
agent_ready="$(oc -n sg-vault-seal get deployment seal-agent -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)"
if [[ "${agent_ready:-0}" -ge 1 ]]; then check "Seal agent: available" ok "${agent_ready}/1 ready"
else check "Seal agent: available" fail "0/1 ready"; fi

# ── VSO CSV (through the Subscription's installedCSV) ─────────────────────────
csv_name="$(oc -n openshift-operators get subscription vault-secrets-operator -o jsonpath='{.status.installedCSV}' 2>/dev/null || true)"
csv_phase="$(oc -n openshift-operators get csv "${csv_name:-none}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
if [[ "${csv_phase}" == "Succeeded" ]]; then check "VSO CSV: Succeeded" ok "${csv_name}"
else check "VSO CSV: Succeeded" fail "csv=${csv_name:-none} phase=${csv_phase:-unknown}"; fi

# ── VSO secrets synced ────────────────────────────────────────────────────────
for vs in VaultStaticSecret/app-config VaultDynamicSecret/db-creds; do
  kind="${vs%%/*}" name="${vs##*/}"
  synced="$(oc -n sg-workloads get "${kind}" "${name}" -o json 2>/dev/null |
    jq -r '[.status.conditions[]? | select(.type == "SecretSynced") | .status] | first // "Unknown"' 2>/dev/null || true)"
  if [[ "${synced}" == "True" ]] && oc -n sg-workloads get secret "${name}" >/dev/null 2>&1; then
    check "VSO: ${kind} ${name} synced" ok "Secret present"
  else
    check "VSO: ${kind} ${name} synced" fail "SecretSynced=${synced:-unknown}"
  fi
done

# ── Deployments available ─────────────────────────────────────────────────────
for d in sg-app/sg-ui sg-app/agent-demo sg-workloads/workload-a sg-workloads/workload-b \
  sg-workloads/postgres sg-identity/openldap sg-identity/keycloak; do
  ns="${d%%/*}" dep="${d##*/}"
  st="$(oc -n "${ns}" get deployment "${dep}" -o json 2>/dev/null || true)"
  if [[ -z "${st}" ]]; then check "Deployment: ${dep} (${ns})" fail "not found"; continue; fi
  avail="$(jq '.status.availableReplicas // 0' <<<"${st}")"
  desired="$(jq '.spec.replicas // 1' <<<"${st}")"
  if [[ "${avail}" -ge "${desired}" && "${desired}" -ge 1 ]]; then
    check "Deployment: ${dep} (${ns})" ok "${avail}/${desired} available"
  else
    check "Deployment: ${dep} (${ns})" fail "${avail}/${desired} available"
  fi
done

# ── Agent demo rendered its file ──────────────────────────────────────────────
demo_pod="$(oc -n sg-app get pod -l app.kubernetes.io/name=agent-demo \
  --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "${demo_pod}" ]]; then
  check "Agent demo: demo-secret rendered" fail "no running agent-demo pod"
elif oc -n sg-app exec "${demo_pod}" -c app -- test -s /vault/secrets/demo-secret 2>/dev/null; then
  check "Agent demo: demo-secret rendered" ok "${demo_pod}"
else
  check "Agent demo: demo-secret rendered" fail "/vault/secrets/demo-secret empty or absent"
fi

# ── Gate files ────────────────────────────────────────────────────────────────
for gate in idempotency drift secret-scan validation; do
  gate_file="${BUILD_DIR}/gates/${gate}.json"
  if [[ ! -f "${gate_file}" ]]; then
    check "Gate: ${gate}" fail "${gate_file#"${ROOT_DIR}"/} not found — run 'make lab'"
    continue
  fi
  # validation.json carries counts; the other gates carry a result.
  result="$(jq -r 'if has("fail_count") then (if .fail_count == 0 and (.pass_count // 0) > 0 then "pass" else "fail" end)
                   else (.result // "unknown") end' "${gate_file}" 2>/dev/null || echo unknown)"
  if [[ "${result}" == "pass" ]]; then check "Gate: ${gate}" ok "pass"
  else check "Gate: ${gate}" fail "${result}"; fi
done

# ── Workloads hold no Vault configuration ─────────────────────────────────────
# The VSO promise: workload pods read files and know nothing about Vault. The
# check reads pod specs (env names and envFrom sources), so it works on every
# container without exec. Expected Vault clients, named on purpose:
#   - sg-app/sg-ui: the console calls Vault with the signed-in user's own
#     token (NUXT_VAULT_ADDR, NUXT_VAULT_NAMESPACE, NUXT_VAULT_CA_FILE);
#   - the vault-agent / vault-agent-init containers of the agent demo.
vault_env_fail=0
for ns in sg-workloads sg-app; do
  pods="$(oc -n "${ns}" get pods --field-selector=status.phase=Running -o json 2>/dev/null || true)"
  if [[ -z "${pods}" ]]; then
    check "No Vault env in ${ns}" fail "cannot list pods"; vault_env_fail=1; continue
  fi
  while IFS=$'\t' read -r pod container names; do
    [[ -z "${pod}" ]] && continue
    if [[ "${ns}/${pod}" == sg-app/sg-ui-* || "${container}" == vault-agent* ]]; then continue; fi
    check "No Vault env: ${ns}/${pod} (${container})" fail "${names}"
    vault_env_fail=1
  done < <(jq -r '.items[] | .metadata.name as $p | (.spec.containers + (.spec.initContainers // []))[] |
      [(.env // [])[].name | select(test("VAULT"; "i"))] as $e |
      [(.envFrom // [])[] | (.configMapRef.name // .secretRef.name // "") | select(test("vault"; "i"))] as $f |
      select(($e + $f) | length > 0) | [$p, .name, (($e + $f) | join(","))] | @tsv' <<<"${pods}")
done
[[ "${vault_env_fail}" -eq 0 ]] &&
  check "No Vault env in workload pods" ok "sg-workloads clean; sg-ui and agent containers are the named exceptions"

# ── Summary ───────────────────────────────────────────────────────────────────
printf '\n  %d ✓  %d ⚠  %d ✗\n\n' "${PASS}" "${WARN}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]] || die "verify-stack: ${FAIL} failure(s) — see ✗ rows above"
ok "verify-stack passed"
