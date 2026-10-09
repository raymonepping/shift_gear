#!/usr/bin/env bash
# scripts/trust.sh — make the Mac (Chrome, Safari, curl via the keychain)
# trust the Shift Gear lab CA so that the console (shiftgear.<apps domain>),
# vault and keycloak load without certificate warnings.
#
#   trust.sh trust     add .secrets/tls/pub/ca.pem to System keychain as trusted root (sudo)
#   trust.sh untrust   remove it again (sudo)
#   trust.sh status    is the CA trusted? does macOS accept the console's certificate?
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
require_cmd security
require_cmd openssl
require_cmd jq

KEYCHAIN=/Library/Keychains/System.keychain
CA="${SECRETS_DIR}/tls/pub/ca.pem"
[[ -s "${CA}" ]] || die "${CA} missing — run make lab first."
openssl x509 -in "${CA}" -noout -ext basicConstraints 2>/dev/null | grep -q 'CA:TRUE' ||
  die "${CA} is not a CA certificate."

subject() { openssl x509 -in "$1" -noout -subject | sed 's/^subject= *//'; }
sha1()    { openssl x509 -in "$1" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :; }
cn()      { openssl x509 -in "$1" -noout -subject -nameopt multiline | sed -n 's/^ *commonName *= *//p'; }

# Trusted = in the System keychain AND listed in admin trust settings.
present() { security find-certificate -a -Z "${KEYCHAIN}" 2>/dev/null | grep -qi "SHA-1 hash: $(sha1 "$1")"; }
trusted() {
  present "$1" || return 1
  security dump-trust-settings -d 2>/dev/null | grep -qF "$(cn "$1")"
}

check_front_door() {
  local apps_domain host
  # The apps domain comes from the contract, never a literal (lesson 19).
  apps_domain="$(jq -r '.cluster.apps_domain // empty' "${BUILD_DIR}/terraform/infra.json" 2>/dev/null || true)"
  if [[ -z "${apps_domain}" ]]; then
    printf '\033[33m!!\033[0m no apps_domain in .build/terraform/infra.json — run make infra\n' >&2
    return 0
  fi
  host="shiftgear.${apps_domain}"
  # Quick TLS handshake; curl uses the keychain on macOS so this reflects
  # whether the CA is actually trusted by the OS.
  if curl --max-time 5 -sS "https://${host}/api/health" -o /dev/null 2>/dev/null; then
    ok "https://${host} — certificate accepted by macOS"
  else
    printf '\033[33m!!\033[0m https://%s — certificate NOT accepted or UI not running (make trust / make ux)\n' "${host}" >&2
  fi
}

case "${1:-status}" in
trust)
  if trusted "${CA}"; then
    info "already trusted: $(subject "${CA}")"
  else
    info "trusting $(subject "${CA}") in the System keychain (will ask for your password)"
    sudo security add-trusted-cert -d -r trustRoot -k "${KEYCHAIN}" "${CA}"
    info "trusted: $(subject "${CA}")"
  fi
  check_front_door
  info "Quit and reopen Chrome (Cmd+Q) so it picks up the new trust."
  ;;
untrust)
  if present "${CA}"; then
    sudo security delete-certificate -Z "$(sha1 "${CA}")" "${KEYCHAIN}" >/dev/null
    info "removed: $(subject "${CA}")"
  else
    info "not in the keychain: $(subject "${CA}")"
  fi
  ;;
status)
  if trusted "${CA}"; then
    info "trusted: $(subject "${CA}")"
  elif present "${CA}"; then
    printf '\033[33m!!\033[0m in keychain but NOT trusted: %s — make trust\n' "$(subject "${CA}")" >&2
  else
    printf '\033[33m!!\033[0m not trusted: %s — make trust\n' "$(subject "${CA}")" >&2
  fi
  check_front_door
  ;;
*) die "usage: trust.sh trust|untrust|status" ;;
esac
