#!/usr/bin/env bash
# scripts/boundary-check.sh — Prove the Terraform/Ansible token boundary.
# Each bootstrap token is asked (sys/capabilities-self) what it may do on
# paths it must and must not touch. Never prints a token value.
# Writes 19 rows: ALLOW or DENY with expected vs actual.
#
# Token files are read from .secrets/tokens/ (Ansible writes them there).
# Seal Vault address is read from .build/terraform/workloads.json (after
# workloads apply); cluster address from .build/terraform/infra.json.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd curl jq

TOKENS_DIR="${ROOT_DIR}/.secrets/tokens"
CA_FILE="${ROOT_DIR}/.secrets/tls/pub/ca.pem"

# Derive Vault addresses from build outputs
INFRA_JSON="${ROOT_DIR}/.build/terraform/infra.json"
APPS_DOMAIN="$(jq -r '.cluster.apps_domain // empty' "${INFRA_JSON}" 2>/dev/null || echo '')"
[[ -n "${APPS_DOMAIN}" ]] || die "Cannot read apps_domain from ${INFRA_JSON}"

SEAL_ADDR="https://vault-seal.${APPS_DOMAIN}"
CLUSTER_ADDR="https://vault.${APPS_DOMAIN}"

# token-file | vault-addr | path | expectation (allow/deny:capability)
# 19 checks: 5 + 4 on the seal Vault, 5 + 5 on the cluster (namespace shift-gear).
mapfile -t checks < <(jq -r --arg seal "${SEAL_ADDR}" --arg cluster "${CLUSTER_ADDR}" \
  '.[] | [.token, (if .vault == "vault-seal" then $seal else $cluster end), .path, .expect] | join("|")' \
  "${ROOT_DIR}/policies/boundary-matrix.json")

fails=0 checked=0
printf '%-22s %-14s %-55s %-13s %-8s\n' TOKEN VAULT PATH EXPECT RESULT

for check in "${checks[@]}"; do
  IFS='|' read -r file addr path expect <<<"${check}"
  # Display name of the Vault: the first DNS label, without the scheme.
  host="${addr#https://}"
  host="${host%%.*}"
  token_file="${TOKENS_DIR}/${file}"
  # Fail closed: a missing token, a missing CA or a failed request is a FAIL,
  # never a pass (an empty answer would otherwise satisfy every "deny" row).
  if [[ ! -s "${token_file}" || ! -f "${CA_FILE}" ]]; then
    printf '%-22s %-14s %-55s %-13s FAIL (missing token or CA)\n' "${file}" "${host}" "${path}" "${expect}" >&2
    fails=$((fails + 1)); checked=$((checked + 1))
    continue
  fi

  if ! resp="$(curl -fsS --cacert "${CA_FILE}" \
    -H "X-Vault-Token: $(<"${token_file}")" \
    -X POST -d "{\"paths\":[\"${path}\"]}" \
    "${addr}/v1/sys/capabilities-self" 2>/dev/null)"; then
    printf '%-22s %-14s %-55s %-13s FAIL (request failed)\n' "${file}" "${host}" "${path}" "${expect}" >&2
    fails=$((fails + 1)); checked=$((checked + 1))
    continue
  fi
  caps="$(jq -r --arg p "${path}" '.[$p] // .capabilities // [] | join(",")' <<<"${resp}")"

  mode="${expect%%:*}" cap="${expect#*:}" has=no
  [[ ",${caps}," == *",${cap},"* || ",${caps}," == *",root,"* ]] && has=yes
  [[ ",${caps}," == *",deny,"* ]] && has=no

  if [[ "${mode}" == "allow" && "${has}" == "yes" ]] || [[ "${mode}" == "deny" && "${has}" == "no" ]]; then
    printf '%-22s %-14s %-55s %-13s PASS\n' "${file}" "${host}" "${path}" "${expect}"
    checked=$((checked + 1))
  else
    printf '%-22s %-14s %-55s %-13s FAIL (caps=%s)\n' "${file}" "${host}" "${path}" "${expect}" "${caps}" >&2
    fails=$((fails + 1))
    checked=$((checked + 1))
  fi
done

echo ""
printf '%d/%d checks passed\n' "$((checked - fails))" "${checked}"
[[ ${checked} -eq 19 ]] || die "expected 19 checks, ran ${checked}"
[[ ${fails} -eq 0 ]] || die "${fails} boundary check(s) failed"
info "Token boundary: all ${checked} checks pass"
