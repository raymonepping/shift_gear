#!/usr/bin/env bash
# scenarios/05_cold_start/run.sh — Cold start: make down then make up.
# Expected: after one unseal key the cluster auto-unseals; make lab changes nothing.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../scripts/common.sh"
require_cmd jq

info "Scenario 05: cold start (make down && make up)"
info "  Step 1: make down"
make -C "${ROOT_DIR}" down

info "  Step 2: make up"
make -C "${ROOT_DIR}" up

info "  Step 3: make verify"
make -C "${ROOT_DIR}" verify

ok "Scenario 05 PASS: cold start successful — cluster auto-unsealed, make verify passed"
info "  Run 'make lab && make lab' to confirm second run is plans-empty and changed=0"
