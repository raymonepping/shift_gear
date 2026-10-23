#!/usr/bin/env bash
# scripts/secret-scan.sh — look for secret material in Terraform state, .build/,
# logs and tracked files (lesson 25). Two checks: every KNOWN value and
# secret-shaped PATTERNS. Prints only file names and labels — never a value.
# Writes .build/gates/secret-scan.json. Exit non-zero on any hit.
#
# Ported from golden_ticket/scripts/secret-scan.sh, adapted for OpenShift:
# known values come from .secrets/ (init files, the four tokens), the seal
# agent's secret-ids (cluster Secrets) and the KV secrets Ansible generated.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ansible-env.sh
source "${SCRIPT_DIR}/ansible-env.sh"
if [[ "${SG_SCAN_MODE:-live}" != offline ]]; then sg_gate_context; fi
exec python3 "${SCRIPT_DIR}/scan-secrets.py" "$@"
