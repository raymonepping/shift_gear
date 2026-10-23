#!/usr/bin/env bash
# scripts/crc-up.sh — Configure, set up and start CRC. Refresh .secrets/kube/config.
# Idempotent: does nothing if CRC is already Running.
# Usage: scripts/crc-up.sh
#
# Sizing rationale (comment preserved here as the canonical source):
#   OpenShift itself idles ~10–11 GB under load.
#   Vault ×4 (seal + 3 Raft), Keycloak, OpenLDAP, Vault Operator,
#   demo workloads, API, UI ≈ 7 GB. 24 GB / 8 vCPU on an Apple Silicon
#   Mac leaves it responsive — provided the Podman machine is stopped.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd crc
require_cmd jq
# oc is required for kubeconfig validation after start; check it lazily

# Accept both .json and .txt — the content is identical JSON with .auths
PULL_SECRET=""
for _f in "${ROOT_DIR}/.secrets/crc/pull-secret.json" "${ROOT_DIR}/.secrets/crc/pull-secret.txt"; do
  [[ -s "${_f}" ]] && { PULL_SECRET="${_f}"; break; }
done
CRC_CPUS=8
CRC_MEMORY_MB=24576
CRC_DISK_GB=80

crc_state() {
  local crc_oc="${HOME}/.crc/bin/oc/oc"
  local kubeconfig="${ROOT_DIR}/.secrets/kube/config"
  local pid_file="${HOME}/.crc/machines/crc/vfkit.pid"
  # `crc status` can block indefinitely when the daemon has lost contact with
  # a stopped vfkit process. The hypervisor PID is authoritative even while
  # the API is briefly slow under load; the API probe handles a stale PID file.
  if [[ -s "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" 2>/dev/null; then
    printf 'Running\n'
  elif [[ -x "${crc_oc}" && -s "${kubeconfig}" ]] &&
     KUBECONFIG="${kubeconfig}" "${crc_oc}" --request-timeout=3s whoami >/dev/null 2>&1; then
    printf 'Running\n'
  elif [[ -d "${HOME}/.crc/machines/crc" ]]; then
    printf 'Stopped\n'
  else
    printf 'Missing\n'
  fi
}

# `crc start` prints kubeadmin and developer passwords on success. Startup is
# routinely captured in proof logs, so redact every password line at source.
crc_start() {
  local output status=0
  output=$(mktemp "${CACHE_DIR}/crc-start.XXXXXX")
  chmod 600 "${output}"
  # Do not pipe `crc start`: vfkit inherits that pipe and exits when the
  # redactor closes it. Capture first, then print only the redacted copy.
  # Isolate the hypervisor's process group from a short-lived controller/PTY.
  # Otherwise a controller session ending can stop vfkit after a healthy boot.
  python3 - "${PULL_SECRET}" "${output}" "${SCRIPT_DIR}/crc-control.sh" <<'PY' || status=$?
import subprocess
import sys
with open(sys.argv[2], 'w') as output:
    process = subprocess.Popen([sys.argv[3], 'start', '-p', sys.argv[1]],
                               stdin=subprocess.DEVNULL, stdout=output,
                               stderr=subprocess.STDOUT, start_new_session=True)
    sys.exit(process.wait())
PY
  sed -E 's/^([[:space:]]*Password:).*/\1 [redacted]/' "${output}"
  rm -f "${output}"
  return "${status}"
}

require_podman_stopped() {
  command -v podman >/dev/null 2>&1 || return 0
  if podman machine list --format '{{.Running}}' 2>/dev/null | grep -q true; then
    if [[ "${ALLOW_PODMAN:-0}" == "1" ]]; then
      warn "Podman machine is running (ALLOW_PODMAN=1) — both VMs will compete for RAM/CPU"
    else
      die "The Podman machine is running. OpenShift Local needs ${CRC_MEMORY_MB} MB and the two VMs
  would compete for memory (past incident: CPU starvation → clock drift → JWT failures).
  Stop it with 'podman machine stop', or re-run with ALLOW_PODMAN=1 to override."
    fi
  fi
}

ensure_config() {
  local key want have
  for kv in "preset=openshift" "cpus=${CRC_CPUS}" "memory=${CRC_MEMORY_MB}" "disk-size=${CRC_DISK_GB}" "consent-telemetry=no"; do
    key="${kv%%=*}" want="${kv#*=}"
    have=$(crc config get "${key}" 2>&1 || true)
    # CRC doesn't persist a value equal to its default: "Default value 'X' is used"
    if [[ "${have}" =~ Default\ value\ \'([^\']*)\' ]]; then
      have="${BASH_REMATCH[1]}"
    else
      have=$(awk -F': ' '{print $NF}' <<<"${have}" | tr -d ' ')
    fi
    if [[ "${have}" != "${want}" ]]; then
      crc config set "${key}" "${want}" >/dev/null
      log "crc config: ${key}=${want} (was: ${have:-unset})"
    fi
  done
}

refresh_kubeconfig() {
  local src="${HOME}/.crc/machines/crc/kubeconfig"
  [[ -s "${src}" ]] || die "CRC admin kubeconfig not found at ${src} — is the VM created?"
  mkdir -p "$(dirname "${ROOT_DIR}/.secrets/kube/config")"
  chmod 700 "${ROOT_DIR}/.secrets" "${ROOT_DIR}/.secrets/kube" 2>/dev/null || true
  install -m 600 "${src}" "${ROOT_DIR}/.secrets/kube/config"
  export KUBECONFIG="${ROOT_DIR}/.secrets/kube/config"
  # Link the matching oc into .cache/bin, which common.sh puts first on PATH,
  # so no script above the substrate needs to know where CRC keeps it.
  if [[ -x "${HOME}/.crc/bin/oc/oc" ]]; then
    mkdir -p "${CACHE_DIR}/bin"
    ln -sf "${HOME}/.crc/bin/oc/oc" "${CACHE_DIR}/bin/oc"
  fi
  if [[ ! -x "${HOME}/.crc/bin/oc/oc" ]] && command -v oc >/dev/null 2>&1; then
    mkdir -p "${CACHE_DIR}/bin"
    local fallback_oc
    fallback_oc="$(command -v oc)"
    [[ "${fallback_oc}" == "${CACHE_DIR}/bin/oc" ]] || ln -sf "${fallback_oc}" "${CACHE_DIR}/bin/oc"
  fi
  if command -v oc >/dev/null 2>&1; then
    # shellcheck disable=SC2015  # oc whoami && ok || warn is intentional
    oc --request-timeout=5s whoami >/dev/null 2>&1 && \
      ok "kubeconfig → .secrets/kube/config ($(oc --request-timeout=5s whoami), $(oc --request-timeout=5s whoami --show-server))" || \
      warn "kubeconfig copied but 'oc whoami' failed — cluster may still be starting"
  else
    ok "kubeconfig → .secrets/kube/config (oc not yet on PATH — run: eval \$(crc oc-env))"
  fi
}

export_ingress_ca() {
  # Export the OpenShift router CA so Ansible can verify Keycloak and console Routes.
  # The CA is stored in the cluster ConfigMap default-ingress-cert.
  # Lesson 19: all paths are substrate-independent strings; only this script knows CRC.
  local dest="${ROOT_DIR}/.secrets/kube/ingress-ca.pem"
  local tmp="${dest}.tmp"
  if command -v oc >/dev/null 2>&1; then
    if oc --request-timeout=10s get -n openshift-config-managed cm/default-ingress-cert \
      -o jsonpath='{.data.ca-bundle\.crt}' >"${tmp}" 2>/dev/null &&
      grep -q 'BEGIN CERTIFICATE' "${tmp}"; then
      install -m 600 "${tmp}" "${dest}"
      rm -f "${tmp}"
      ok "ingress CA → .secrets/kube/ingress-ca.pem"
    else
      rm -f "${tmp}"
      warn "Could not export ingress CA — Ansible prepare will fail if it cannot find ${dest}"
    fi
  else
    warn "oc not found — skipping ingress CA export (run eval \$(crc oc-env) and re-run make crc-up)"
  fi
}

# Validate pull secret exists and is valid JSON
[[ -n "${PULL_SECRET}" ]] || die "Pull secret missing: place it at .secrets/crc/pull-secret.json (or .txt).
  Download it from https://console.redhat.com/openshift/create/local (it is gitignored)."
jq -e '.auths' "${PULL_SECRET}" >/dev/null 2>&1 || die "${PULL_SECRET} is not a valid pull secret (expected JSON with .auths)"

STATE=$(crc_state)
info "CRC state: ${STATE}"

if [[ "${STATE}" == "Running" ]]; then
  ok "CRC already running — skipping start"
  ensure_config  # records desired sizing; takes effect on next start
elif [[ "${STATE}" == "Stopped" ]]; then
  # VM exists (was created by this project or a previous run after crc-delete).
  require_podman_stopped
  ensure_config
  info "Starting existing CRC VM..."
  crc_start
else
  # Not created — full setup
  require_podman_stopped
  ensure_config
  if ! crc setup --check-only >/dev/null 2>&1; then
    info "Running crc setup (first time)..."
    crc setup
  fi
  info "Starting CRC (first start ≈ 10–15 min; later starts ≈ 3–5 min)..."
  crc_start
fi

refresh_kubeconfig
export_ingress_ca

# Post-start: force clock sync inside the VM (lesson: Mac sleep → clock drift)
"${SCRIPT_DIR}/crc-post-start.sh"

OPENSHIFT_VERSION=$(oc --request-timeout=10s version -o json 2>/dev/null |
  jq -r '.openshiftVersion // .serverVersion.gitVersion // "unknown"')
ok "CRC is running. OpenShift version: ${OPENSHIFT_VERSION}"
