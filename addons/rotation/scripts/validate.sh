#!/usr/bin/env bash
# addons/rotation/scripts/validate.sh — offline gate for the KV rotation add-on
# (make rotation-validate; also run in CI). No cluster, no Vault.
set -euo pipefail
ADDON_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="$(CDPATH='' cd -- "${ADDON_DIR}/../.." && pwd)"
PY="$(head -1 "$(readlink -f "$(command -v ansible-playbook)")" | sed 's/^#!//' | tr -d ' ')"

failures=0
pass() { printf '\033[32m ok\033[0m %s\n' "$1"; }
fail() { printf '\033[31m FAIL\033[0m %s\n' "$1"; failures=$((failures + 1)); }

# 1. Controller unit tests (stdlib unittest; the runtime is stdlib-only).
if "${PY}" -m unittest discover -s "${ADDON_DIR}/controller/tests" -p 'test_*.py' >/tmp/rotation-unit.$$ 2>&1; then
  pass "controller unit tests ($(grep -Eo 'Ran [0-9]+ tests' /tmp/rotation-unit.$$))"
else
  cat /tmp/rotation-unit.$$ >&2
  fail "controller unit tests"
fi
rm -f /tmp/rotation-unit.$$

# 2. The shipped configuration parses and validates.
if "${PY}" -c "import sys; sys.path.insert(0, '${ADDON_DIR}/controller'); from rotation.config import load; c = load('${ADDON_DIR}/rotation.yaml'); print(len(c.secrets))" >/dev/null; then
  pass "rotation.yaml is valid"
else
  fail "rotation.yaml is invalid"
fi

# 3. Terraform: fmt, validate, test (mock providers).
tf="${ADDON_DIR}/terraform"
if terraform -chdir="${tf}" init -backend=false -input=false -lockfile=readonly >/dev/null &&
  terraform fmt -recursive -check "${tf}" >/dev/null &&
  terraform -chdir="${tf}" validate -no-color >/dev/null &&
  terraform -chdir="${tf}" test -no-color >/dev/null; then
  pass "terraform fmt / validate / test (add-on root)"
else
  fail "terraform fmt / validate / test (add-on root)"
fi

# 4. The add-on runs the same pinned Vault image as the core agents.
core_vault="$(grep -Eo 'docker.io/hashicorp/vault-enterprise:[^"]+@sha256:[0-9a-f]{64}' "${ROOT_DIR}/terraform/workloads/main.tf" | sort -u)"
addon_vault="$(grep -Eo 'docker.io/hashicorp/vault-enterprise:[^"]+@sha256:[0-9a-f]{64}' "${tf}/variables.tf" | sort -u)"
if [[ -n "${addon_vault}" && "${core_vault}" == *"${addon_vault}"* ]]; then
  pass "vault image digest matches the core"
else
  fail "vault image digest differs from terraform/workloads"
fi

# 5. Ansible: syntax-check + ansible-lint (production).
export ANSIBLE_CONFIG="${ROOT_DIR}/ansible.cfg"
export ANSIBLE_ROLES_PATH="${ADDON_DIR}/ansible/roles:${ROOT_DIR}/ansible/roles"
export ANSIBLE_COLLECTIONS_PATH="${ROOT_DIR}/.cache/ansible/collections"
syntax_ok=1
for pb in "${ADDON_DIR}"/ansible/rotation-*.yml; do
  ansible-playbook --syntax-check "${pb}" >/dev/null 2>&1 || { syntax_ok=0; echo "syntax: ${pb}" >&2; }
done
if [[ "${syntax_ok}" == 1 ]]; then
  pass "ansible syntax-check"
else
  fail "ansible syntax-check"
fi
if command -v ansible-lint >/dev/null 2>&1; then
  if (cd "${ADDON_DIR}/ansible" && ansible-lint --profile production -q . >/tmp/rotation-lint.$$ 2>&1); then
    pass "ansible-lint (production)"
  else
    cat /tmp/rotation-lint.$$ >&2
    fail "ansible-lint (production)"
  fi
  rm -f /tmp/rotation-lint.$$
fi

# 6. ShellCheck on the add-on scripts.
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x --source-path="${ROOT_DIR}/scripts" "${ADDON_DIR}"/scripts/*.sh; then
    pass "shellcheck"
  else
    fail "shellcheck"
  fi
fi

# 7. Secure Door consumer (prompt 01_09): unit tests, board server, its root, design sync, lint.
consumer="${ADDON_DIR}/consumer"
if [[ -d "${consumer}" ]]; then
  if "${PY}" -W ignore -m unittest discover -s "${consumer}/consumer/tests" -p 'test_*.py' >/tmp/consumer-unit.$$ 2>&1; then
    pass "consumer unit tests ($(grep -Eo 'Ran [0-9]+ tests' /tmp/consumer-unit.$$))"
  else
    cat /tmp/consumer-unit.$$ >&2
    fail "consumer unit tests"
  fi
  rm -f /tmp/consumer-unit.$$
  if node --test "${consumer}/board/server.test.mjs" >/tmp/board-unit.$$ 2>&1; then
    pass "board server tests ($(grep -Eo 'tests [0-9]+' /tmp/board-unit.$$ | head -1))"
  else
    cat /tmp/board-unit.$$ >&2
    fail "board server tests"
  fi
  rm -f /tmp/board-unit.$$
  if python3 "${consumer}/scripts/sync-board-css.py" --check >/dev/null; then
    pass "board design tokens match the console (main.css)"
  else
    fail "board tokens.css is out of date — run addons/rotation/consumer/scripts/sync-board-css.py"
  fi
  ctf="${consumer}/terraform"
  if terraform -chdir="${ctf}" init -backend=false -input=false -lockfile=readonly >/dev/null &&
    terraform fmt -recursive -check "${ctf}" >/dev/null &&
    terraform -chdir="${ctf}" validate -no-color >/dev/null &&
    terraform -chdir="${ctf}" test -no-color >/dev/null; then
    pass "terraform fmt / validate / test (consumer root)"
  else
    fail "terraform fmt / validate / test (consumer root)"
  fi
  csyntax=1
  for pb in "${consumer}"/ansible/consumer-*.yml; do
    ansible-playbook --syntax-check "${pb}" >/dev/null 2>&1 || { csyntax=0; echo "syntax: ${pb}" >&2; }
  done
  if [[ "${csyntax}" == 1 ]]; then pass "consumer ansible syntax-check"; else fail "consumer ansible syntax-check"; fi
  if command -v ansible-lint >/dev/null 2>&1; then
    if (cd "${consumer}/ansible" && ANSIBLE_ROLES_PATH="${consumer}/ansible/roles" ansible-lint --profile production -q . >/tmp/consumer-lint.$$ 2>&1); then
      pass "consumer ansible-lint (production)"
    else
      cat /tmp/consumer-lint.$$ >&2
      fail "consumer ansible-lint (production)"
    fi
    rm -f /tmp/consumer-lint.$$
  fi
  if command -v shellcheck >/dev/null 2>&1 && shellcheck -x --source-path="${ROOT_DIR}/scripts" "${consumer}"/scripts/*.sh; then
    pass "consumer shellcheck"
  else
    fail "consumer shellcheck"
  fi
fi

echo
if [[ "${failures}" -eq 0 ]]; then
  printf '\033[32mrotation-validate: all checks passed\033[0m\n'
else
  printf '\033[31mrotation-validate: %d check(s) failed\033[0m\n' "${failures}"
  exit 1
fi
