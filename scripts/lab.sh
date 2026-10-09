#!/usr/bin/env bash
# scripts/lab.sh — make lab: the complete, phased, fail-closed workflow.
#
# Runs every phase from scripts/phases.txt in order (Terraform builds the house,
# Ansible decorates it), then the three gates: idempotency (every Ansible phase
# again, changed=0), Terraform drift (every plan empty), secret scan.
# Only on full success: writes .build/convergence.json and .build/layers.json.
# On any failure: prints the exact phase and resume command.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=phases.sh
source "${SCRIPT_DIR}/phases.sh"
require_cmd jq

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
digest="$("${SCRIPT_DIR}/automation-digest.sh")"
banner() { printf '\n\033[1;7m %s \033[0m %s\n\n' "$1" "$2" >&2; }
fail() {
  printf '\n\033[31m%s failed.\033[0m Fix the reported error, then resume with:\n  make %s && make lab\n' \
    "$1" "$2" >&2
  exit 1
}

mapfile -t PHASES < <(phases)
total=$(( ${#PHASES[@]} + 3 ))

timings="{}"
n=0
for entry in "${PHASES[@]}"; do
  read -r tool name <<<"${entry}"
  n=$((n + 1))
  banner "${n}/${total}" "${tool} ${name}"
  t0=$(date +%s)
  case "${tool}" in
  tf)
    if ! compgen -G "${TF_DIR}/${name}/main.tf" >/dev/null; then
      warn "==> lab: stopped before tf ${name} (not implemented yet)"
      warn "    Implement terraform/${name}/ and re-run: make ${name} && make lab"
      exit 0
    fi
    "${SCRIPT_DIR}/tf-run.sh" "${name}" apply || fail "tf ${name}" "${name}"
    ;;
  ansible)
    playbook_path="${ROOT_DIR}/ansible/${name}.yml"
    if [[ ! -f "${playbook_path}" ]]; then
      warn "==> lab: stopped before ansible ${name} (not implemented yet)"
      warn "    Implement ansible/${name}.yml and re-run: make ${name} && make lab"
      exit 0
    fi
    "${SCRIPT_DIR}/ansible-run.sh" "${name}" || fail "ansible ${name}" "${name}"
    ;;
  esac
  timings="$(jq --arg p "${name}" --argjson s "$(($(date +%s) - t0))" '.[$p] = $s' <<<"${timings}")"
done

n=$((n + 1))
banner "${n}/${total}" "gate: idempotency (every Ansible phase again, changed=0)"
"${SCRIPT_DIR}/idempotency.sh" || fail "The idempotency gate" "idempotency"

n=$((n + 1))
banner "${n}/${total}" "gate: Terraform drift (every plan empty)"
TF_ONLY=1 "${SCRIPT_DIR}/drift.sh" || fail "The Terraform drift gate" "drift"

n=$((n + 1))
banner "${n}/${total}" "gate: secret scan"
"${SCRIPT_DIR}/secret-scan.sh" || fail "The secret scan" "secret-scan"

umask 022
jq -n \
  --arg playbook "scripts/lab.sh" \
  --arg started "${started_at}" \
  --arg finished "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg digest "${digest}" \
  --argjson phases "$(printf '%s\n' "${PHASES[@]}" | \
    jq -R 'split(" ") | {tool: .[0], phase: .[1]}' | jq -s .)" \
  --argjson timings "${timings}" \
  '{result: "success", playbook: $playbook, phases: $phases,
    phase_seconds: $timings, started_at: $started,
    finished_at: $finished, automation_digest: $digest}' \
  >"${BUILD_DIR}/convergence.json.tmp"
mv "${BUILD_DIR}/convergence.json.tmp" "${BUILD_DIR}/convergence.json"

# Sync evidence ConfigMap one last time
if grep -qE '^ansible[[:space:]]+ux$' "${SCRIPT_DIR}/phases.txt" && \
   [[ -f "${ROOT_DIR}/ansible/ux.yml" ]]; then
  # The full ux play: the build is skipped when the UI source is unchanged.
  "${SCRIPT_DIR}/ansible-run.sh" ux >/dev/null
fi

banner "done" "shift-gear converged — digest ${digest:0:12}, evidence in .build/"
