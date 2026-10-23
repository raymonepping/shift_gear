#!/usr/bin/env bash
# scripts/automation-digest.sh — SHA-256 over sorted relative paths + contents
# of ansible/**/*.{yml,yaml,j2}, policies/**/*.hcl, terraform/**/*.tf,
# deploy/**, ansible.cfg and scripts/phases.txt.
# Used by lab.sh to stamp convergence; UI compares against stored stamp.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

python3 "${SCRIPT_DIR}/input-digest.py"
