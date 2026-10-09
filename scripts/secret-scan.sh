#!/usr/bin/env bash
# scripts/secret-scan.sh — look for secret material in Terraform state, .build/,
# logs and tracked files (lesson 25). Two checks: every KNOWN value and
# secret-shaped PATTERNS. Prints only file names and labels — never a value.
# Writes .build/gates/secret-scan.json. Exit non-zero on any hit.
#
# Ported from golden_ticket/scripts/secret-scan.sh, adapted for OpenShift:
# known values come from .secrets/ (init files, the four tokens), the seal
# agent's secret-ids (cluster Secrets) and the KV secrets Ansible generated.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ansible-env.sh
source "${SCRIPT_DIR}/ansible-env.sh"
require_cmd jq

declare -A values=()
[[ -n "${VAULT_LICENSE:-}" ]] && values[license]="${VAULT_LICENSE:0:64}"

# The four bootstrap tokens and any other token file.
while IFS= read -r f; do
  values["token:${f#"${SECRETS_DIR}"/}"]="$(tr -d '\n' <"${f}")"
done < <(find "${SECRETS_DIR}/tokens" -type f 2>/dev/null)

# Init material of both Vaults (HTTP API and CLI field names).
for f in seal-init vault-init; do
  json="${SECRETS_DIR}/${f}.json"
  [[ -f "${json}" ]] || continue
  values["${f}-root"]="$(jq -r '.root_token' "${json}")"
  i=0
  while IFS= read -r key; do
    values["${f}-key${i}"]="${key}"
    i=$((i + 1))
  done < <(jq -r '[.keys_base64, .keys, .unseal_keys_b64, .recovery_keys_base64, .recovery_keys, .recovery_keys_b64] | map(. // []) | add | .[]' "${json}")
done

# Private keys under .secrets/tls (one body line each is enough to recognise a copy).
while IFS= read -r f; do
  values["tls-key:${f##*/}"]="$(sed -n '2p' "${f}")"
done < <(find "${SECRETS_DIR}/tls" -maxdepth 1 -name '*.key' 2>/dev/null)

# The seal agent's and the rotator's live secret-ids (cluster Secrets, never printed).
if command -v oc >/dev/null 2>&1 && [[ -s "${KUBECONFIG:-}" ]]; then
  for s in seal-agent-approle seal-rotator-approle; do
    while IFS=$'\t' read -r key value; do
      [[ -n "${key}" ]] && values["secret:${s}/${key}"]="${value}"
    done < <(oc -n sg-vault-seal get secret "${s}" -o json 2>/dev/null |
      jq -r '.data // {} | to_entries[] | select(.key | test("secret")) | "\(.key)\t\(.value | @base64d)"' || true)
  done
fi

# Every value Ansible generated into Vault KV (kv/shift-gear/*), read with
# Ansible's own token through the Route.
apps_domain="$(jq -r '.cluster.apps_domain // empty' "${BUILD_DIR}/terraform/infra.json" 2>/dev/null || true)"
if [[ -n "${apps_domain}" && -s "${SECRETS_DIR}/tokens/ansible-platform" ]]; then
  addr="https://vault.${apps_domain}"
  auth=(-H "X-Vault-Token: $(<"${SECRETS_DIR}/tokens/ansible-platform")" -H "X-Vault-Namespace: shift-gear")
  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    while IFS=$'\t' read -r key value; do
      [[ -n "${key}" ]] && values["kv:${path}${key}"]="${value}"
    done < <(curl -fsS --cacert "${SECRETS_DIR}/tls/pub/ca.pem" "${auth[@]}" \
      "${addr}/v1/kv/data/shift-gear/${path}" 2>/dev/null |
      jq -r '.data.data // {} | to_entries[] | select(.value | type == "string") | "\(.key)\t\(.value)"' || true)
  done < <(curl -fsS --cacert "${SECRETS_DIR}/tls/pub/ca.pem" "${auth[@]}" -X LIST \
    "${addr}/v1/kv/metadata/shift-gear/" 2>/dev/null | jq -r '.data.keys // [] | .[] | select(endswith("/") | not)' || true)
fi

targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then
  targets=("${BUILD_DIR}")
  while IFS= read -r f; do targets+=("${f}"); done < <(find "${CACHE_DIR}" -maxdepth 1 -name '*.log' 2>/dev/null)
  while IFS= read -r f; do targets+=("${f}"); done < <(
    find "${SECRETS_DIR}/terraform" "${SECRETS_DIR}/archive" -type f \
      \( -name '*.tfstate' -o -name '*.tfstate.*' \) 2>/dev/null
  )
  while IFS= read -r f; do targets+=("${ROOT_DIR}/${f}"); done < <(git -C "${ROOT_DIR}" ls-files 2>/dev/null)
fi

hits=0
for label in "${!values[@]}"; do
  value="${values[$label]}"
  [[ ${#value} -ge 8 ]] || continue
  if files="$(grep -rlF -- "${value}" "${targets[@]}" 2>/dev/null)"; then
    printf 'LEAK: %s found in %s\n' "${label}" "${files//$'\n'/, }" >&2
    hits=$((hits + 1))
  fi
done

# Secret-shaped patterns: Vault service/batch/recovery tokens, the licence
# header, PEM private keys with a base64 body (whole-file match, -z).
patterns=('hv[sbr]\.[A-Za-z0-9_-]{20,}' '02MV4UU43BK[5]' '-----BEGIN [A-Z ]*PRIVATE KEY-----[[:space:]]+[A-Za-z0-9+/=]{40}')
for pattern in "${patterns[@]}"; do
  if files="$(grep -rlzE -- "${pattern}" "${targets[@]}" 2>/dev/null)"; then
    printf 'LEAK: pattern %s found in %s\n' "${pattern%%[\\\[]*}…" "${files//$'\n'/, }" >&2
    hits=$((hits + 1))
  fi
done

# Every state file and backup 0600.
while IFS= read -r f; do
  perms="$(stat -f '%OLp' "${f}" 2>/dev/null || stat -c '%a' "${f}" 2>/dev/null || echo '?')"
  if [[ "${perms}" != "600" ]]; then
    printf 'PERM: %s is %s (expected 600)\n' "${f#"${ROOT_DIR}"/}" "${perms}" >&2
    hits=$((hits + 1))
  fi
done < <(find "${SECRETS_DIR}/terraform" -type f \( -name '*.tfstate' -o -name '*.tfstate.backup' \) 2>/dev/null)

mkdir -p "${BUILD_DIR}/gates"
jq -n \
  --arg result "$([[ ${hits} -eq 0 ]] && echo pass || echo fail)" \
  --argjson hits "${hits}" --argjson values "${#values[@]}" --argjson targets "${#targets[@]}" \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{gate: "secret-scan", result: $result, hits: $hits, known_values: $values, targets: $targets, at: $at}' \
  >"${BUILD_DIR}/gates/secret-scan.json"

[[ ${hits} -eq 0 ]] || die "${hits} secret leak(s) found — see output above"
info "Secret scan clean: ${#values[@]} known values + ${#patterns[@]} patterns over ${#targets[@]} target(s)"
