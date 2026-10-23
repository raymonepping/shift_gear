#!/usr/bin/env bash
# Retire the legacy JWT only after a new login through the projected reviewer.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
sg_lock "$@"
require_kubeconfig
pod="$(oc -n sg-app get pod -l app.kubernetes.io/name=agent-demo --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
[[ -n "${pod}" ]] || die "No running Agent demo to verify Kubernetes auth"
oc -n sg-app exec "${pod}" -c vault-agent -- sh -ec '
  export VAULT_ADDR=https://vault-active.sg-vault.svc:8200 VAULT_CACERT=/vault/userconfig/sg-ca/ca.pem VAULT_NAMESPACE=shift-gear
  token=$(vault write -field=token auth/kubernetes/login role=sg-agent-demo jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token)
  VAULT_TOKEN="$token" vault token revoke -self >/dev/null
' >/dev/null
oc -n sg-vault delete secret vault-token-reviewer-token --ignore-not-found >/dev/null
python3 "${SCRIPT_DIR}/state-audit.py"
ok "Projected reviewer login proved; legacy Secret retired; current state clean. Protected backups require custody review."
