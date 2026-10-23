#!/usr/bin/env bash
# Same-root leaf renewal and serving-chain proof. Never replaces the CA.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
sg_lock "$@"
require_kubeconfig
ca_before="$(openssl x509 -in "${SECRETS_DIR}/tls/pub/ca.pem" -noout -fingerprint -sha256)"
leaf_before="$(openssl x509 -in "${SECRETS_DIR}/tls/pub/vault.crt" -noout -fingerprint -sha256)"
backup="${SECRETS_DIR}/tls-renewal/$(date -u +%Y%m%dT%H%M%SZ)"
umask 077
mkdir -p "${backup}"
cp -R "${SECRETS_DIR}/tls/." "${backup}/"
trap 'warn "Renewal did not finish. Previous TLS files remain under ${backup}; follow docs/credential-operations.md before retrying."' ERR
SG_TLS_RENEW_LEAVES=1 make -C "${ROOT_DIR}" prepare
[[ "$(openssl x509 -in "${SECRETS_DIR}/tls/pub/ca.pem" -noout -fingerprint -sha256)" == "${ca_before}" ]] || die "CA changed unexpectedly"
[[ "$(openssl x509 -in "${SECRETS_DIR}/tls/pub/vault.crt" -noout -fingerprint -sha256)" != "${leaf_before}" ]] || die "Leaf certificate was not renewed"
# The seal Vault is a single instance; main Vault continues using its open seal.
oc -n sg-vault-seal delete pod vault-seal-0 --wait=true
oc -n sg-vault-seal wait pod/vault-seal-0 --for=condition=Ready --timeout=180s
make -C "${ROOT_DIR}" unseal
oc -n sg-vault-seal rollout restart deployment/seal-agent
oc -n sg-vault-seal rollout status deployment/seal-agent --timeout=180s
oc -n sg-identity rollout restart deployment/keycloak
oc -n sg-identity rollout status deployment/keycloak --timeout=180s
"${SCRIPT_DIR}/vault-roll.sh"
VERIFY_SCOPE=runtime make -C "${ROOT_DIR}" verify boundary
python3 - <<'PY'
import hashlib, json, os, socket, ssl
from pathlib import Path
root = Path(os.environ['ROOT_DIR'])
domain = json.loads((root / '.build/terraform/infra.json').read_text())['cluster']['apps_domain']
ctx = ssl.create_default_context(cafile=str(root / '.secrets/tls/pub/ca.pem'))
for host, cert in [('vault', 'vault'), ('vault-seal', 'vault-seal')]:
    with socket.create_connection((f'{host}.{domain}', 443), timeout=10) as raw:
        with ctx.wrap_socket(raw, server_hostname=f'{host}.{domain}') as conn:
            actual = conn.getpeercert(binary_form=True)
    expected = ssl.PEM_cert_to_DER_cert((root / f'.secrets/tls/pub/{cert}.crt').read_text())
    assert hashlib.sha256(actual).digest() == hashlib.sha256(expected).digest(), f'{host}: old serving certificate'
print('PASS: same CA, renewed leaves served with verified TLS; Vault and boundaries passed.')
PY
