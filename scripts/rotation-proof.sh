#!/usr/bin/env bash
# scripts/rotation-proof.sh — make rotation-proof (prompt 02, scenario 03).
# Runs the real rotator twice (a Job from CronJob seal-rotator) and proves:
#   - the secret-id the agent held before is gone from the seal Vault,
#   - the secret-id the agent holds now exists,
#   - exactly one secret-id exists for sg-seal-autounseal.
# Logins cannot prove this from the controller: the AppRole is bound to the
# cluster's pod network, so a login from here is refused by design. The proof
# uses secret-id/lookup with Ansible's own seal token instead.
# Reads secrets from the cluster and .secrets/; never prints one.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
require_cmd jq
require_cmd oc
require_cmd curl
require_kubeconfig

apps_domain="$(jq -r '.cluster.apps_domain // empty' "${BUILD_DIR}/terraform/infra.json" 2>/dev/null || true)"
[[ -n "${apps_domain}" ]] || die "No apps_domain in .build/terraform/infra.json — run 'make infra'"
seal_addr="https://vault-seal.${apps_domain}"
ca="${SECRETS_DIR}/tls/pub/ca.pem"
token_file="${SECRETS_DIR}/tokens/ansible-seal"
[[ -s "${token_file}" ]] || die "Missing ${token_file#"${ROOT_DIR}"/} — run 'make seal-init'"
role=sg-seal-autounseal
ns=sg-vault-seal

agent_secret_id() {
  oc -n "${ns}" get secret seal-agent-approle -o jsonpath='{.data.secret-id}' | base64 -d
}

# 200 when the secret-id exists, 204/404 when it does not.
lookup_status() {
  jq -n --arg s "$1" '{secret_id: $s}' |
    curl -s -o /dev/null -w '%{http_code}' --cacert "${ca}" \
      -H "X-Vault-Token: $(<"${token_file}")" -X POST --data @- \
      "${seal_addr}/v1/auth/approle/role/${role}/secret-id/lookup"
}

run_rotator() {
  local job
  job="rotation-proof-$(date +%s)-$1"
  oc -n "${ns}" create job "${job}" --from=cronjob/seal-rotator >/dev/null
  if ! oc -n "${ns}" wait --for=condition=complete "job/${job}" --timeout=180s >/dev/null 2>&1; then
    oc -n "${ns}" logs "job/${job}" --all-containers 2>&1 | tail -5 >&2
    die "rotator job ${job} did not complete"
  fi
  oc -n "${ns}" logs "job/${job}" -c rotator 2>/dev/null | tail -1 >&2
  oc -n "${ns}" delete job "${job}" >/dev/null 2>&1 || true
}

info "rotation-proof: run the rotator twice"
before="$(agent_secret_id)"
[[ -n "${before}" ]] || die "Secret seal-agent-approle has no secret-id — run 'make agent'"
run_rotator 1
run_rotator 2
after="$(agent_secret_id)"

fails=0
check() { if [[ "$2" == "$3" ]]; then ok "$1"; else printf '\033[31m FAIL\033[0m %s (got %s)\n' "$1" "$2" >&2; fails=$((fails + 1)); fi; }

if [[ "${before}" != "${after}" ]]; then ok "the agent holds a new secret-id"; else
  printf '\033[31m FAIL\033[0m the agent secret-id did not change\n' >&2; fails=$((fails + 1)); fi
old_status="$(lookup_status "${before}")"
if [[ "${old_status}" != "200" ]]; then ok "the previous secret-id is gone (lookup ${old_status})"; else
  printf '\033[31m FAIL\033[0m the previous secret-id still exists\n' >&2; fails=$((fails + 1)); fi
check "the current secret-id exists (lookup 200)" "$(lookup_status "${after}")" 200
count="$(curl -s --cacert "${ca}" -H "X-Vault-Token: $(<"${token_file}")" -X LIST \
  "${seal_addr}/v1/auth/approle/role/${role}/secret-id" | jq '.data.keys | length')"
check "exactly one secret-id for ${role}" "${count}" 1

[[ ${fails} -eq 0 ]] || die "rotation-proof: ${fails} check(s) failed"
info "rotation-proof: PASS"
