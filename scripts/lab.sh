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
sg_lock "$@"
# shellcheck source=phases.sh
source "${SCRIPT_DIR}/phases.sh"
require_cmd jq

export SG_RUN_ID
SG_RUN_ID="$(python3 "${SCRIPT_DIR}/run-record.py" start)"
export SG_CLUSTER_ID
SG_CLUSTER_ID="$(jq -r .clusterId "${BUILD_DIR}/run.json")"
record_exit() {
  local status=$?
  if [[ "${status}" -ne 0 ]]; then
    if [[ "$(jq -r .provisioning "${BUILD_DIR}/run.json")" == success ]]; then
      python3 "${SCRIPT_DIR}/run-record.py" publication failed
    else
      python3 "${SCRIPT_DIR}/run-record.py" provisioning failed
    fi
    python3 "${SCRIPT_DIR}/run-record.py" publish-status || warn "Latest attempt is saved locally; status publication failed."
  fi
  return "${status}"
}
trap record_exit EXIT
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

# fmt_duration <seconds> → "NmNNs"
fmt_duration() {
  local s=$1
  printf '%dm%02ds' "$((s / 60))" "$((s % 60))"
}

phase_timings="{}"
phase_order=()
n=0
for entry in "${PHASES[@]}"; do
  read -r tool name <<<"${entry}"
  n=$((n + 1))
  banner "${n}/${total}" "${tool} ${name}"
  python3 "${SCRIPT_DIR}/run-record.py" step "${name}" running
  t0=$(date +%s)
  case "${tool}" in
  tf)
    if ! compgen -G "${TF_DIR}/${name}/main.tf" >/dev/null; then
      warn "==> lab: stopped before tf ${name} (not implemented yet)"
      warn "    Implement terraform/${name}/ and re-run: make ${name} && make lab"
      exit 1
    fi
    "${SCRIPT_DIR}/tf-run.sh" "${name}" apply || fail "tf ${name}" "${name}"
    ;;
  ansible)
    playbook_path="${ROOT_DIR}/ansible/${name}.yml"
    if [[ ! -f "${playbook_path}" ]]; then
      warn "==> lab: stopped before ansible ${name} (not implemented yet)"
      warn "    Implement ansible/${name}.yml and re-run: make ${name} && make lab"
      exit 1
    fi
    "${SCRIPT_DIR}/ansible-run.sh" "${name}" || fail "ansible ${name}" "${name}"
    ;;
  *) die "Unknown phase tool: ${tool}" ;;
  esac
  python3 "${SCRIPT_DIR}/run-record.py" step "${name}" passed
  elapsed="$(($(date +%s) - t0))"
  phase_timings="$(jq --arg p "${name}" --argjson s "${elapsed}" '.[$p] = $s' <<<"${phase_timings}")"
  phase_order+=("${tool}|${name}|${elapsed}")
done

gate_timings="{}"
gate_order=()

n=$((n + 1))
banner "${n}/${total}" "gate: idempotency (every Ansible phase again, changed=0)"
t0=$(date +%s)
python3 "${SCRIPT_DIR}/run-record.py" step "gate:idempotency" running
"${SCRIPT_DIR}/idempotency.sh" || fail "The idempotency gate" "idempotency"
python3 "${SCRIPT_DIR}/run-record.py" step "gate:idempotency" passed
elapsed="$(($(date +%s) - t0))"
gate_timings="$(jq --arg g "idempotency" --argjson s "${elapsed}" '.[$g] = $s' <<<"${gate_timings}")"
gate_order+=("idempotency|${elapsed}")

n=$((n + 1))
banner "${n}/${total}" "gate: Terraform drift (every plan empty)"
t0=$(date +%s)
python3 "${SCRIPT_DIR}/run-record.py" step "gate:drift" running
TF_ONLY=1 "${SCRIPT_DIR}/drift.sh" || fail "The Terraform drift gate" "drift"
python3 "${SCRIPT_DIR}/run-record.py" step "gate:drift" passed
elapsed="$(($(date +%s) - t0))"
gate_timings="$(jq --arg g "drift" --argjson s "${elapsed}" '.[$g] = $s' <<<"${gate_timings}")"
gate_order+=("drift|${elapsed}")

n=$((n + 1))
banner "${n}/${total}" "gate: secret scan"
t0=$(date +%s)
python3 "${SCRIPT_DIR}/run-record.py" step "gate:secret-scan" running
"${SCRIPT_DIR}/secret-scan.sh" || fail "The secret scan" "secret-scan"
python3 "${SCRIPT_DIR}/run-record.py" step "gate:secret-scan" passed
elapsed="$(($(date +%s) - t0))"
gate_timings="$(jq --arg g "secret-scan" --argjson s "${elapsed}" '.[$g] = $s' <<<"${gate_timings}")"
gate_order+=("secret-scan|${elapsed}")

finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
[[ "$("${SCRIPT_DIR}/automation-digest.sh")" == "${digest}" ]] || die "Automation inputs changed during this run; rerun make lab on stable inputs."
lab_start_epoch="$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "${started_at}" +%s 2>/dev/null \
                   || date -d "${started_at}" +%s)"
lab_end_epoch="$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "${finished_at}" +%s 2>/dev/null \
                 || date -d "${finished_at}" +%s)"
total_seconds="$(( lab_end_epoch - lab_start_epoch ))"

umask 022
jq -n \
  --arg run_id "${SG_RUN_ID}" --arg cluster_id "${SG_CLUSTER_ID}" \
  --arg playbook "scripts/lab.sh" \
  --arg started "${started_at}" \
  --arg finished "${finished_at}" \
  --arg digest "${digest}" \
  --argjson phases "$(printf '%s\n' "${PHASES[@]}" | \
    jq -R 'split(" ") | {tool: .[0], phase: .[1]}' | jq -s .)" \
  --argjson phase_seconds "${phase_timings}" \
  --argjson gate_seconds "${gate_timings}" \
  --argjson total_seconds "${total_seconds}" \
  '{result: "success", run_id: $run_id, cluster_id: $cluster_id, playbook: $playbook, phases: $phases,
    phase_seconds: $phase_seconds, gate_seconds: $gate_seconds,
    total_seconds: $total_seconds,
    started_at: $started, finished_at: $finished,
    automation_digest: $digest}' \
  >"${BUILD_DIR}/convergence.json.tmp"
mv "${BUILD_DIR}/convergence.json.tmp" "${BUILD_DIR}/convergence.json"

python3 "${SCRIPT_DIR}/run-record.py" provisioning success
# Sync evidence ConfigMap one last time
if grep -qE '^ansible[[:space:]]+ux$' "${SCRIPT_DIR}/phases.txt" && \
   [[ -f "${ROOT_DIR}/ansible/ux.yml" ]]; then
  # The full ux play: the build is skipped when the UI source is unchanged.
  "${SCRIPT_DIR}/ansible-run.sh" ux >/dev/null
fi

# ── Timing summary ───────────────────────────────────────────────────────────
printf '\n\033[1m%-16s %-12s %s\033[0m\n' "phase" "tool" "time"
for entry in "${phase_order[@]}"; do
  IFS='|' read -r tool name secs <<<"${entry}"
  tool_label="$([[ "${tool}" == "tf" ]] && echo "terraform" || echo "ansible")"
  printf '%-16s %-12s %s\n' "${name}" "${tool_label}" "$(fmt_duration "${secs}")"
done
for entry in "${gate_order[@]}"; do
  IFS='|' read -r name secs <<<"${entry}"
  printf '%-16s %-12s %s\n' "${name}" "gate" "$(fmt_duration "${secs}")"
done
printf '%-16s %-12s %s\n' "total" "" "$(fmt_duration "${total_seconds}")"

python3 "${SCRIPT_DIR}/run-record.py" publication success
python3 "${SCRIPT_DIR}/run-record.py" publish-status
cp "${BUILD_DIR}/convergence.json" "${BUILD_DIR}/last-success.json"
trap - EXIT
banner "done" "shift-gear converged — digest ${digest:0:12}, evidence in .build/"
