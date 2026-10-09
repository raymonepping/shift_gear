#!/usr/bin/env bash
# scripts/tf-run.sh — Run Terraform for one root with the project environment.
#
#   scripts/tf-run.sh <infra|foundation|workloads|seal|platform> <init|plan|apply|drift|test|output> [args...]
#
# - VAULT_NAMESPACE is always unset before any run (lesson 16: double-prefix bug).
# - Vault provider credentials come only from .secrets/tokens/tf-<root>.
# - After every apply the root's non-secret outputs are written to
#   .build/terraform/<root>.json for Ansible to consume (lesson 14).
# - Every state file is forced to 0600 after each command.
# - drift = plan -detailed-exitcode: 0 clean, 2 drift, anything else error.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=ansible-env.sh
source "${SCRIPT_DIR}/ansible-env.sh"

require_cmd terraform
require_cmd jq

root="${1:?usage: tf-run.sh <root> <action> [args...]}"
action="${2:?usage: tf-run.sh <root> <action> [args...]}"
shift 2

dir="${TF_DIR}/${root}"
[[ -d "${dir}" ]] || die "Unknown Terraform root: ${root} (expected: infra, foundation, workloads, seal, platform)"

# Lesson 16: always unset VAULT_NAMESPACE before any Terraform run.
unset VAULT_NAMESPACE

# ── Vault provider credentials ───────────────────────────────────────────────
# Only seal and platform roots need a Vault token. The token is never passed
# through TF_VAR_* and is never echoed.
case "${root}" in
seal | platform)
  if [[ "${action}" != "test" && "${action}" != "init" ]]; then
    token_file="${SECRETS_DIR}/tokens/tf-${root}"
    [[ -s "${token_file}" ]] || die "Missing ${token_file#"${ROOT_DIR}"/}: run the bootstrap phase first."
    # Vault address derived from the contract (.build/terraform/infra.json);
    # never a literal domain (lesson 19).
    infra_json="${BUILD_DIR}/terraform/infra.json"
    apps_domain="$(jq -r '.cluster.apps_domain // empty' "${infra_json}" 2>/dev/null || true)"
    [[ -n "${apps_domain}" ]] || die "No apps_domain in ${infra_json#"${ROOT_DIR}"/}: run 'make infra' first."
    case "${root}" in
    seal)     export VAULT_ADDR="https://vault-seal.${apps_domain}" ;;
    platform) export VAULT_ADDR="https://vault.${apps_domain}" ;;
    esac
    _vault_token="$(<"${token_file}")"
    export VAULT_TOKEN="${_vault_token}"
    export VAULT_CACERT="${SECRETS_DIR}/tls/pub/ca.pem"
  fi
  ;;
esac

# ── Kubeconfig for kubernetes/helm providers ──────────────────────────────────
if [[ -s "${SECRETS_DIR}/kube/config" ]]; then
  export KUBE_CONFIG_PATH="${SECRETS_DIR}/kube/config"
fi

# ── State security ─────────────────────────────────────────────────────────
secure_state() {
  find "${SECRETS_DIR}/terraform/${root}" -maxdepth 1 -type f \
    \( -name 'terraform.tfstate' -o -name 'terraform.tfstate.*' \) \
    -exec chmod 600 {} + 2>/dev/null || true
  find "${TF_DIR}/${root}" -maxdepth 1 -type f \
    \( -name 'terraform.tfstate' -o -name 'terraform.tfstate.*' \) \
    -exec chmod 600 {} + 2>/dev/null || true
}
trap secure_state EXIT

# ── Record helper for .build/terraform/<root>.json ───────────────────────────
# Run records live in <root>.runs.json: <root>.json holds only the outputs and
# is rewritten after every apply (it overwrote the records before).
record() {
  mkdir -p "${BUILD_DIR}/terraform"
  local f="${BUILD_DIR}/terraform/${root}.runs.json" now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [[ -s "${f}" ]] || echo '{}' >"${f}"
  jq --arg k "$1" --arg v "$2" --arg now "${now}" \
    '.[$k] = {result: $v, at: $now}' "${f}" >"${f}.tmp" && mv "${f}.tmp" "${f}"
}

write_outputs() {
  mkdir -p "${BUILD_DIR}/terraform"
  local f="${BUILD_DIR}/terraform/${root}.json"
  # Write only non-sensitive outputs; sensitive ones are marked in HCL and
  # will appear as null — that is intentional.
  terraform -chdir="${dir}" output -json 2>/dev/null | \
    jq 'with_entries(select(.value.sensitive == false or .value.sensitive == null))
        | with_entries(.value = .value.value)' \
    >"${f}.tmp" && mv "${f}.tmp" "${f}"
  chmod 600 "${f}"
}

# ── Init before every action ─────────────────────────────────────────────────
# Idempotent and quick when nothing changed; also re-initialises a root whose
# backend configuration changed (a stale .terraform/ is not enough).
if [[ "${action}" != "init" ]]; then
  terraform -chdir="${dir}" init -input=false >/dev/null ||
    die "terraform init failed in terraform/${root}"
fi

# ── Dispatch ────────────────────────────────────────────────────────────────
case "${action}" in
init)
  terraform -chdir="${dir}" init -input=false -upgrade
  ;;
plan)
  terraform -chdir="${dir}" plan -input=false "$@"
  ;;
apply)
  terraform -chdir="${dir}" apply -input=false -auto-approve "$@"
  record last_apply success
  write_outputs
  # Post-apply plan (Option A): proves the apply left no residual drift and
  # populates last_plan so the Layers page shows "plan empty" right after
  # make lab, not "not checked". Uses -out=/dev/null to avoid a .tfplan file.
  set +e
  terraform -chdir="${dir}" plan -input=false -detailed-exitcode -lock=false -out=/dev/null "$@"
  _plan_rc=$?
  set -e
  case "${_plan_rc}" in
  0)
    record last_plan clean
    ;;
  2)
    record last_plan drift
    printf '\033[33mWARN:\033[0m terraform/%s post-apply plan is not empty — run make drift\n' "${root}" >&2
    ;;
  *)
    record last_plan error
    die "terraform/${root}: post-apply plan failed (rc=${_plan_rc})"
    ;;
  esac
  ;;
destroy)
  terraform -chdir="${dir}" destroy -input=false "$@"
  ;;
output)
  terraform -chdir="${dir}" output "$@"
  ;;
test)
  terraform -chdir="${dir}" test "$@"
  ;;
drift)
  set +e
  terraform -chdir="${dir}" plan -input=false -detailed-exitcode -lock=false "$@"
  rc=$?
  set -e
  case "${rc}" in
  0)
    record last_plan clean
    info "terraform/${root}: no drift"
    ;;
  2)
    record last_plan drift
    printf '\033[33mDRIFT:\033[0m terraform/%s — the plan is not empty\n' "${root}" >&2
    exit 2
    ;;
  *)
    record last_plan error
    die "terraform/${root}: plan failed (rc=${rc})"
    ;;
  esac
  ;;
*)
  die "Unknown action: ${action} (expected: init, plan, apply, destroy, output, test, drift)"
  ;;
esac
