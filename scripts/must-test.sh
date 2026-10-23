#!/usr/bin/env bash
# Use Ansible's Python: PyYAML is already a required controller dependency.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export ANSIBLE_LOCAL_TEMP="${SCRIPT_DIR}/../.cache/ansible/tmp"
mkdir -p "${ANSIBLE_LOCAL_TEMP}"
python_bin="$(head -1 "$(readlink -f "$(command -v ansible-playbook)")" | sed 's/^#!//' | tr -d ' ')"
"${python_bin}" -m unittest discover -s "${SCRIPT_DIR}/../tests" -p 'test_*.py'
