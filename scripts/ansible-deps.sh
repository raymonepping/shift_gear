#!/usr/bin/env bash
# scripts/ansible-deps.sh — install the pinned collections into the ignored
# project cache (make deps; make check depends on it).
#
# ansible-galaxy skips a requirement that any collection path already
# satisfies — including the collections bundled with a Homebrew ansible — so
# a pinned collection could silently come from elsewhere and be invisible to
# ansible-lint's own environment. Force the install whenever a pinned
# collection is not in the project cache at its pinned version (golden_ticket D5).
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ansible-env.sh
source "${SCRIPT_DIR}/ansible-env.sh"

require_cmd ansible-galaxy
req="${ROOT_DIR}/ansible/requirements.yml"
dest="${CACHE_DIR}/ansible/collections"
force=()
while read -r name version; do
  ns="${name%%.*}"
  coll="${name#*.}"
  [[ -d "${dest}/ansible_collections/${ns}/${coll}" && -d "${dest}/ansible_collections/${name}-${version}.info" ]] ||
    force=(--force)
done < <(awk '/- name:/{n=$3} /version:/{print n, $2}' "${req}")

ansible-galaxy collection install ${force[@]+"${force[@]}"} \
  --requirements-file "${req}" --collections-path "${dest}" </dev/null |
  grep -v -E 'Nothing to do|already installed' || true
ok "Ansible collections pinned in .cache/ansible/collections"
