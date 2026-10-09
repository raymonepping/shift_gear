#!/usr/bin/env bash
# scripts/tls.sh — Project CA + Vault/seal-agent TLS certificates.
#
# Idempotent:
#   - Creates the CA once (10 years) at .secrets/tls/ca.{pem,key}
#   - (Re)issues server/client certs when missing, expiring within 30 days,
#     not signed by the current CA, or lacking a required SAN
#   - Derives the apps_domain from the infra Terraform output (.build/terraform/infra.json)
#     so the Route hostnames stay substrate-independent
#
# Certificates issued:
#   vault-seal  — vault-seal.sg-vault-seal.svc  (standalone seal Vault)
#   vault       — vault.sg-vault.svc / *.vault-internal (HA cluster, shared cert)
#   seal-agent  — seal-agent.sg-vault-seal.svc   (mTLS proxy listener)
#
# Lessons applied:
#   19: hostnames from the contract, not hard-coded
#   23: notBefore = -1h (clock-skew prevention)
#   24: serverAuth + clientAuth EKUs (Vault pods present certs to seal-agent mTLS listener)
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

require_cmd openssl jq oc

KEYS="${ROOT_DIR}/.secrets/tls"
PUB="${ROOT_DIR}/.secrets/tls/pub"
RENEW_WITHIN=$((30 * 86400))
mkdir -p "${KEYS}" "${PUB}"
chmod 700 "${KEYS}"
umask 077

# Read apps_domain from the infra output (substrate-independent)
INFRA_JSON="${ROOT_DIR}/.build/terraform/infra.json"
if [[ -s "${INFRA_JSON}" ]]; then
  APPS_DOMAIN="$(jq -r '.cluster.apps_domain // empty' "${INFRA_JSON}" 2>/dev/null || echo '')"
fi
if [[ -z "${APPS_DOMAIN:-}" ]]; then
  die "Cannot read apps_domain from ${INFRA_JSON} — run: make infra"
fi

# Report a real change with a CHANGED marker (the prepare play keys changed_when on it).
changed() { printf 'CHANGED %s\n' "$*"; ok "$*"; }

# oc apply from stdin; CHANGED only when the object was created or configured.
apply_object() {
  local what=$1 out
  out=$(oc apply -f - 2>&1) || die "oc apply failed for ${what}: ${out}"
  if grep -qE ' (created|configured)$' <<<"${out}"; then
    changed "${what}"
  else
    ok "${what} unchanged"
  fi
}

ensure_ca() {
  if [[ -s "${KEYS}/ca.key" ]] && [[ -s "${PUB}/ca.pem" ]] &&
     openssl x509 -checkend "${RENEW_WITHIN}" -noout -in "${PUB}/ca.pem" >/dev/null 2>&1; then
    ok "CA valid until $(openssl x509 -enddate -noout -in "${PUB}/ca.pem" | cut -d= -f2)"
    return
  fi
  log "Creating project CA (10 years, notBefore -1h)"
  # notBefore one hour back on the CA too (lesson 23): a CA that starts "now"
  # by the Mac's clock is not yet valid on a node whose clock lags, and every
  # chain below it fails ("tls: bad certificate").
  openssl req -x509 -newkey rsa:3072 -nodes -sha256 \
    -not_before "$(date -u -v-1H '+%Y%m%d%H%M%SZ' 2>/dev/null || date -u --date='-1 hour' '+%Y%m%d%H%M%SZ')" \
    -not_after "$(date -u -v+10y '+%Y%m%d%H%M%SZ' 2>/dev/null || date -u --date='+10 years' '+%Y%m%d%H%M%SZ')" \
    -subj "/O=Shift Gear/CN=Shift Gear Project CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -keyout "${KEYS}/ca.key" -out "${PUB}/ca.pem" 2>/dev/null
  chmod 600 "${KEYS}/ca.key"
  chmod 644 "${PUB}/ca.pem"
  changed "CA created"
}

# issue <name> <CN> <SANs comma-separated>
issue() {
  local name=$1 cn=$2 sans=$3
  local crt="${PUB}/${name}.crt" key="${KEYS}/${name}.key" missing=""
  if [[ -s "${crt}" ]] && [[ -s "${key}" ]]; then
    local text
    text=$(openssl x509 -noout -text -in "${crt}")
    for san in ${sans//,/ }; do
      grep -qF "${san/IP:/IP Address:}" <<<"${text}" || missing="${missing} ${san}"
    done
    if [[ -z "${missing}" ]] &&
       openssl x509 -checkend "${RENEW_WITHIN}" -noout -in "${crt}" >/dev/null 2>&1 &&
       openssl verify -CAfile "${PUB}/ca.pem" "${crt}" >/dev/null 2>&1; then
      ok "${name} cert valid until $(openssl x509 -enddate -noout -in "${crt}" | cut -d= -f2)"
      return
    fi
  fi
  log "Issuing ${name} certificate${missing:+ (missing SANs:${missing})}"
  local ext; ext=$(mktemp)
  # notBefore offset: -1h from now (lesson 23 — clock-skew prevention)
  local not_before
  not_before=$(date -u -v-1H '+%Y%m%d%H%M%SZ' 2>/dev/null || date -u --date='-1 hour' '+%Y%m%d%H%M%SZ')
  cat >"${ext}" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=${sans}
EOF
  openssl req -new -newkey rsa:3072 -nodes -sha256 \
    -subj "/O=Shift Gear/CN=${cn}" \
    -keyout "${key}" -out "${KEYS}/${name}.csr" 2>/dev/null
  openssl x509 -req -sha256 -days 365 \
    -in "${KEYS}/${name}.csr" \
    -CA "${PUB}/ca.pem" -CAkey "${KEYS}/ca.key" -CAcreateserial -CAserial "${KEYS}/ca.srl" \
    -extfile "${ext}" \
    -not_before "${not_before}" \
    -out "${crt}" 2>/dev/null
  rm -f "${ext}" "${KEYS}/${name}.csr"
  chmod 600 "${key}"
  chmod 644 "${crt}"
  changed "${name} cert issued (365 days, notBefore -1h, serverAuth+clientAuth)"
}

apply_secret() {
  local ns=$1 secret=$2 cert_name=$3
  oc -n "${ns}" create secret generic "${secret}" \
    --from-file=tls.crt="${PUB}/${cert_name}.crt" \
    --from-file=tls.key="${KEYS}/${cert_name}.key" \
    --from-file=ca.crt="${PUB}/ca.pem" \
    --dry-run=client -o yaml | apply_object "Secret ${ns}/${secret}"
}

apply_ca_configmap() {
  local ns
  for ns in sg-vault-seal sg-vault sg-identity sg-workloads sg-app; do
    oc -n "${ns}" create configmap sg-ca \
      --from-file=ca.pem="${PUB}/ca.pem" \
      --dry-run=client -o yaml | apply_object "ConfigMap ${ns}/sg-ca"
  done
}

apply_license_secret() {
  local license="${VAULT_LICENSE:-}"
  if [[ -z "${license}" ]]; then
    die "VAULT_LICENSE is not set — source .env first"
  fi
  for ns in sg-vault-seal sg-vault; do
    # From stdin, so the licence never appears in a process argument list.
    printf '%s' "${license}" |
      oc -n "${ns}" create secret generic vault-license --from-file=license=/dev/stdin \
        --dry-run=client -o yaml | apply_object "Secret ${ns}/vault-license"
  done
}

# ── CA ───────────────────────────────────────────────────────────────────────
ensure_ca

# ── seal Vault certificate ────────────────────────────────────────────────────
issue "vault-seal" "vault-seal.sg-vault-seal.svc" \
  "DNS:vault-seal,DNS:vault-seal.sg-vault-seal.svc,DNS:vault-seal.sg-vault-seal.svc.cluster.local,DNS:vault-seal-0.vault-seal-internal,DNS:vault-seal.${APPS_DOMAIN}"

# ── main Vault cluster (shared certificate for all 3 pods) ───────────────────
# One cert with all pod names and SANs (Raft peer mTLS uses the same cert).
issue "vault" "vault.sg-vault.svc" \
  "DNS:vault,DNS:vault.sg-vault.svc,DNS:vault.sg-vault.svc.cluster.local,DNS:vault-active.sg-vault.svc,DNS:vault-active.sg-vault.svc.cluster.local,DNS:vault-0.vault-internal,DNS:vault-0.vault-internal.sg-vault.svc.cluster.local,DNS:vault-1.vault-internal,DNS:vault-1.vault-internal.sg-vault.svc.cluster.local,DNS:vault-2.vault-internal,DNS:vault-2.vault-internal.sg-vault.svc.cluster.local,DNS:vault.${APPS_DOMAIN},IP:127.0.0.1"

# ── seal agent certificate (serverAuth+clientAuth for the mTLS proxy listener) ─
issue "seal-agent" "seal-agent.sg-vault-seal.svc" \
  "DNS:seal-agent,DNS:seal-agent.sg-vault-seal.svc,DNS:seal-agent.sg-vault-seal.svc.cluster.local"

# ── Keycloak HTTPS certificate ────────────────────────────────────────────────
# Keycloak runs on port 8443 with its own TLS cert. The Route uses reencrypt,
# so the router re-encrypts from the client to the pod using this cert.
issue "keycloak" "keycloak.sg-identity.svc" \
  "DNS:keycloak,DNS:keycloak.sg-identity.svc,DNS:keycloak.sg-identity.svc.cluster.local,DNS:keycloak.${APPS_DOMAIN}"

require_kubeconfig

# ── Apply Kubernetes Secrets ──────────────────────────────────────────────────
apply_secret sg-vault-seal vault-seal-tls vault-seal
apply_secret sg-vault      vault-tls      vault
apply_secret sg-vault-seal seal-agent-tls seal-agent
# keycloak-tls is applied in the sg-identity namespace
apply_secret sg-identity   keycloak-tls   keycloak

# ── Vault Enterprise licence Secret ──────────────────────────────────────────
apply_license_secret

# ── CA ConfigMaps ─────────────────────────────────────────────────────────────
apply_ca_configmap

ok "TLS setup complete (apps_domain=${APPS_DOMAIN})"
