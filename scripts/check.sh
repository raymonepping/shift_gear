#!/usr/bin/env bash
# scripts/check.sh — Static gate: no cluster required.
# Checks: bash syntax, ShellCheck, terraform fmt/validate/test per root,
# sg_stats unit tests, substrate grep (lesson 19), no sensitive paths tracked.
# Prompt 06 adds ansible --syntax-check and ansible-lint (production profile).
#
# Usage: make check
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# Bash ≥ 4 guard (macOS /bin/bash is 3.2)
[[ "${BASH_VERSINFO[0]}" -ge 4 ]] || die "bash ≥ 4 required (macOS /bin/bash is 3.2 — use /usr/local/bin/bash or brew install bash)"

PASS=0 FAIL=0
pass()  { ok  "$*";        PASS=$((PASS+1)); }
fail()  { warn "FAIL: $*"; FAIL=$((FAIL+1)); }

# 1. Shell syntax (bash -n)
all_ok=true
for script in "${ROOT_DIR}"/scripts/*.sh; do
  if ! bash -n "${script}" 2>/dev/null; then
    all_ok=false; warn "bash -n failed: ${script##*/}"
  fi
done
if ${all_ok}; then pass "Shell syntax (bash -n)"; else fail "Shell syntax (bash -n)"; fi

# 2. ShellCheck
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x --source-path="${ROOT_DIR}/scripts" "${ROOT_DIR}"/scripts/*.sh; then
    pass "ShellCheck"
  else
    fail "ShellCheck (run: shellcheck -x scripts/*.sh)"
  fi
else
  warn "shellcheck not installed — skipping (brew install shellcheck)"
fi

# 3. Terraform fmt (all roots)
if terraform fmt -check -recursive "${TF_DIR}" >/dev/null 2>&1; then
  pass "terraform fmt"
else
  fail "terraform fmt (run: terraform fmt -recursive terraform/)"
fi

# 4. Terraform validate + test per root
for root in "${TF_DIR}"/*/; do
  name="$(basename "${root}")"
  # Skip old roots that have been superseded
  [[ "${name}" =~ ^(vault-seal|vault|vault-config|tests)$ ]] && continue
  [[ -d "${root}" ]] || continue
  if [[ ! -d "${root}.terraform" ]]; then
    terraform -chdir="${root}" init -input=false -backend=false -no-color >/dev/null 2>&1 || true
  fi
  if terraform -chdir="${root}" validate -no-color >/dev/null 2>&1; then
    pass "terraform validate: ${name}"
  else
    fail "terraform validate: ${name}"
  fi
  if compgen -G "${root}tests/*.tftest.hcl" >/dev/null 2>&1; then
    if terraform -chdir="${root}" test -no-color >/dev/null 2>&1; then
      pass "terraform test: ${name}"
    else
      fail "terraform test: ${name}"
    fi
  fi
done

# 5. Substrate isolation grep (lesson 19)
# Only terraform/infra/ and scripts/crc-*.sh may reference the substrate
# (Terraform, Ansible, deploy/, policies/ and every other script are checked).
substrate_violations=$(
  {
    grep -rnE 'crc|vfkit|api\.crc\.testing|apps-crc\.testing' \
      "${TF_DIR}/foundation" "${TF_DIR}/workloads" "${TF_DIR}/seal" "${TF_DIR}/platform" \
      "${ROOT_DIR}/ansible" "${ROOT_DIR}/deploy" "${ROOT_DIR}/policies" \
      --include='*.tf' --include='*.yml' --include='*.yaml' --include='*.hcl' \
      --include='*.j2' --include='*.sh' --include='*.json' 2>/dev/null
    grep -nE 'crc|vfkit|api\.crc\.testing|apps-crc\.testing' "${ROOT_DIR}"/scripts/*.sh 2>/dev/null |
      grep -v '/scripts/crc-[a-z-]*\.sh:' | grep -v '/scripts/check\.sh:'
  } | grep -v '\.terraform/' |
    # Naming the operator's Make targets (make crc-up …) is not substrate knowledge.
    grep -vE 'make crc-[a-z]+' |
    # Calling a crc-*.sh script by path is delegation, not direct substrate knowledge.
    grep -vE 'crc-[a-z-]+\.sh' || true
)
if [[ -z "${substrate_violations}" ]]; then
  pass "Substrate isolation (no substrate refs outside infra/ and crc-*.sh)"
else
  fail "Substrate isolation violated — substrate refs found outside infra/ and crc-*.sh:"
  printf '%s\n' "${substrate_violations}" >&2
fi

# 6. sg_stats unit tests
if [[ -f "${ROOT_DIR}/tests/test_sg_stats.py" ]]; then
  ansible_python="$(head -1 "$(readlink -f "$(command -v ansible-playbook 2>/dev/null)")" 2>/dev/null \
    | sed 's/^#!//' | tr -d ' ' || echo python3)"
  if "${ansible_python}" -m unittest -q "${ROOT_DIR}/tests/test_sg_stats.py" 2>/dev/null; then
    pass "sg_stats unit tests"
  else
    fail "sg_stats unit tests"
  fi
fi

# 7. Ansible syntax-check (all playbooks — prompt 06 also adds ansible-lint)
if compgen -G "${ROOT_DIR}/ansible/*.yml" >/dev/null 2>&1; then
  all_ok=true
  for playbook in "${ROOT_DIR}"/ansible/*.yml; do
    base="$(basename "${playbook}")"
    [[ "${base}" == "requirements.yml" ]] && continue
    if ! ansible-playbook --syntax-check "${playbook}" </dev/null >/dev/null 2>&1; then
      all_ok=false; warn "ansible syntax-check failed: ${base}"
    fi
  done
  if ${all_ok}; then pass "Ansible syntax-check"; else fail "Ansible syntax-check"; fi
fi

# 8. ansible-lint (production profile — added by prompt 06)
if command -v ansible-lint >/dev/null 2>&1 && [[ -d "${ROOT_DIR}/ansible" ]]; then
  if (cd "${ROOT_DIR}" && ansible-lint --profile production -q ansible </dev/null >/dev/null 2>&1); then
    pass "ansible-lint (production)"
  else
    fail "ansible-lint (production)"
  fi
fi

# 9. No sensitive paths staged or tracked by git
# Check only staged/tracked files (not untracked) — .build/ and .cache/ are
# untracked by design (listed in .gitignore); the check is for accidental git add.
if git -C "${ROOT_DIR}" ls-files --cached 2>/dev/null | \
  grep -qE '(^|/)(\.env$|\.secrets/|\.build/|\.cache/)|\.(key|hclic|pem|tfstate|tfplan)$|tfstate\.backup|vault-init\.json|seal-init\.json|(^|/)tokens/'; then
  fail "Sensitive or generated paths are tracked by git — run: git rm --cached <path>"
else
  pass "No sensitive paths tracked"
fi

echo ""
printf '%d checks passed, %d failed\n' "${PASS}" "${FAIL}"
[[ "${FAIL}" -eq 0 ]] || exit 1
