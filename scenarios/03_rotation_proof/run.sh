#!/usr/bin/env bash
# scenarios/03_rotation_proof/run.sh — Two AppRole secret-id rotations.
# Delegates to scripts/rotation-proof.sh.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/../../scripts/rotation-proof.sh"
