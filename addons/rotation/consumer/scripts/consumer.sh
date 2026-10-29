#!/usr/bin/env bash
# addons/rotation/consumer/scripts/consumer.sh — lifecycle of the Secure Door consumer.
#
#   consumer.sh up|down|status|logs|test
#
# Its own namespace and Terraform root (scripts/tf-run.sh rotation-consumer …),
# independent of the rotation controller: `make rotation-down` never touches it,
# and `down` here never touches the controller, the secret or its history.
set -euo pipefail
CONSUMER_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=ansible-env.sh
source "${CONSUMER_DIR}/../../../scripts/ansible-env.sh"

export ANSIBLE_ROLES_PATH="${CONSUMER_DIR}/ansible/roles:${ROOT_DIR}/ansible/roles"
export SG_STATS_DIR="${BUILD_DIR}/addons/rotation/ansible-stats"
mkdir -p "${BUILD_DIR}/addons/rotation" "${SG_STATS_DIR}"

TF="${ROOT_DIR}/scripts/tf-run.sh"
NS="sg-rotation-consumer"
STATE="${SECRETS_DIR}/terraform/rotation-consumer/terraform.tfstate"
SECRET="api-key/secure-door"
PY="$(head -1 "$(readlink -f "$(command -v ansible-playbook)")" | sed 's/^#!//' | tr -d ' ')"

playbook() {
  local name="$1"
  shift
  (cd "${ROOT_DIR}" && SG_PHASE="rotation-consumer-${name}" ansible-playbook "${CONSUMER_DIR}/ansible/consumer-${name}.yml" "$@" </dev/null)
}
installed() { oc get namespace "${NS}" >/dev/null 2>&1; }
state_has_resources() { [[ -s "${STATE}" ]] && [[ "$(jq '.resources | length' "${STATE}" 2>/dev/null || echo 0)" -gt 0 ]]; }
board_url() { jq -r '.board_url // empty' "${BUILD_DIR}/terraform/rotation-consumer.json" 2>/dev/null || true; }

secret_onboarded() {
  "${PY}" - "${ROOT_DIR}" <<'PY'
import json, ssl, sys, urllib.request, urllib.error
root = sys.argv[1]
dom = json.load(open(f"{root}/.build/terraform/infra.json"))["cluster"]["apps_domain"]
tok = open(f"{root}/.secrets/tokens/ansible-platform").read().strip()
req = urllib.request.Request(f"https://vault.{dom}/v1/kv/metadata/shift-gear/rotation/api-key/secure-door",
                             headers={"X-Vault-Token": tok, "X-Vault-Namespace": "shift-gear"})
try:
    urllib.request.urlopen(req, context=ssl.create_default_context(cafile=f"{root}/.secrets/tls/pub/ca.pem"), timeout=10)
    sys.exit(0)
except urllib.error.HTTPError as e:
    sys.exit(1 if e.code == 404 else 2)
PY
}

cmd="${1:-}"
[[ -n "${cmd}" ]] || die "usage: consumer.sh up|down|status|logs|test"
shift

case "${cmd}" in
up)
  info "Secure Door: preflight (the watched secret must be managed by the rotation add-on)"
  if ! secret_onboarded; then
    if oc get namespace sg-rotation >/dev/null 2>&1; then
      info "  ${SECRET} is not onboarded yet — applying the rotation add-on's config (make rotation-up)"
      "${ROOT_DIR}/addons/rotation/scripts/rotation.sh" up
    else
      die "${SECRET} does not exist and the rotation add-on is not installed — run make rotation-up first"
    fi
  fi
  info "Secure Door: Vault configuration (one Kubernetes auth role per party)"
  playbook configure
  mode="grace ${GRACE:-30}s"
  [[ "${GRACE:-30}" == 0 ]] && mode="strict"
  info "Secure Door: Terraform (verifier, client, board, Route, NetworkPolicies, two read-only policies; ${mode})"
  "${TF}" rotation-consumer apply -no-color ${GRACE:+-var=grace_seconds=${GRACE}} >"${BUILD_DIR}/addons/rotation/consumer-tf-apply.log" 2>&1 ||
    { tail -40 "${BUILD_DIR}/addons/rotation/consumer-tf-apply.log" >&2; die "terraform apply (rotation-consumer) failed"; }
  grep -E '^(Apply complete|No changes)' "${BUILD_DIR}/addons/rotation/consumer-tf-apply.log" || true
  info "Secure Door: proof (each party current vs Vault, client granted, isolation, board over TLS)"
  playbook verify
  ok "Secure Door is up — board: $(board_url)   logs: make rotation-consumer-logs"
  ;;

down)
  if ! installed && ! state_has_resources; then
    playbook down >/dev/null
    ok "Secure Door consumer not installed — nothing to remove"
    exit 0
  fi
  "${TF}" rotation-consumer destroy-auto -no-color >"${BUILD_DIR}/addons/rotation/consumer-tf-destroy.log" 2>&1 ||
    { tail -40 "${BUILD_DIR}/addons/rotation/consumer-tf-destroy.log" >&2; die "terraform destroy (rotation-consumer) failed"; }
  grep -E '^Destroy complete' "${BUILD_DIR}/addons/rotation/consumer-tf-destroy.log" || true
  playbook down
  ok "Secure Door removed — ${SECRET}, its versions and history stay in Vault; the controller keeps rotating it"
  ;;

status)
  if ! installed; then echo "Secure Door consumer: not installed (make rotation-consumer-up)"; exit 2; fi
  oc -n "${NS}" get pods -l 'app.kubernetes.io/name in (door-verifier,door-client,door-board)' -o wide
  for party in verifier client; do
    oc -n "${NS}" exec -i "deploy/door-${party}" -c "${party}" -- python3 - <<'PY' || echo "${party}: status not available yet"
import json, urllib.request
d = json.load(urllib.request.urlopen("http://127.0.0.1:9090/status", timeout=3))
v, a = d["vault"], d["agent"]
lr = a["last_refresh"]
refresh = "last success %s" % lr["at"] if lr["observable"] else "not observable; last change rendered %s" % a["last_change_rendered_at"]
if d["role"] == "verifier":
    b = d["verifier"]
    ring = ", ".join("v%s%s" % (k["version"], " (current)" if k["current"] else " until %s" % k["retires_at"]) for k in b["ring"])
    print("verifier    mode=%s grace=%ss ring=[%s] state=%s since %s" % (b["mode"], int(b["grace_seconds"]), ring, b["state"], d["started_at"]))
    print("            decisions %s" % (", ".join("%s=%s" % kv for kv in sorted(b["verdicts"].items())) or "none yet"))
else:
    b = d["client"]
    last = b.get("last") or {}
    print("client      v%s fp=%s state=%s (%s) since %s" % (b["version"], b["fingerprint"], b["state"], b["reason"], d["started_at"]))
    print("            last %s v%s (%s); outcomes %s" % (last.get("verdict", "-"), last.get("version", "-"), last.get("reason", "-"),
          ", ".join("%s=%s" % kv for kv in sorted(b["outcomes"].items())) or "none"))
    w = b["windows"]
    print("            denial windows %d%s" % (len(w), "; last %s denied in %ss (%s)" % (w[0]["denied"], w[0]["seconds"], w[0]["reason"]) if w else ""))
    f, r = b["latency"]["vault_to_file_s"], b["latency"]["file_to_reload_s"]
    print("            vault->file p50=%s max=%s n=%s   file->reload p50=%s max=%s n=%s" % (f["p50"], f["max"], f["n"], r["p50"], r["max"], r["n"]))
print("            refresh %s; vault %s (%s), reachability only" % (refresh, v["probe"], v["detail"]))
PY
  done
  echo "board       $(board_url)"
  ;;

logs)
  installed || die "Secure Door consumer not installed"
  party="${P:-client}"
  [[ "${party}" == verifier || "${party}" == client || "${party}" == board ]] || die "P must be verifier, client or board"
  container="${party}"
  case "${C:-}" in agent) container=vault-agent ;; probe) container=vault-probe ;; esac
  [[ "${party}" == board ]] && container=board
  follow=(-f)
  [[ "${F:-1}" == 0 ]] && follow=()
  exec oc -n "${NS}" logs "deploy/door-${party}" -c "${container}" --tail=100 ${follow[@]+"${follow[@]}"}
  ;;

test)
  exec "${PY}" -u "${CONSUMER_DIR}/tests/live/run.py" "$@"
  ;;

*)
  die "unknown command: ${cmd}"
  ;;
esac
