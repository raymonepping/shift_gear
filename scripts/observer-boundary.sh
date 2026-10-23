#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
require_kubeconfig
python3 - <<'PY'
import datetime as dt
import json
from pathlib import Path
import subprocess

checks = [('get', 'vaultstaticsecrets.secrets.hashicorp.com/app-config', True),
          ('get', 'vaultdynamicsecrets.secrets.hashicorp.com/db-creds', True),
          ('get', 'deployments.apps/workload-a', True), ('get', 'deployments.apps/workload-b', True),
          ('get', 'secrets/app-config', False), ('list', 'secrets', False),
          ('list', 'deployments.apps', False), ('get', 'deployments.apps/unrelated', False),
          ('patch', 'deployments.apps/workload-a', False), ('create', 'pods/exec', False)]
checks = [('sg-workloads', *check) for check in checks] + [
    ('sg-vault-seal', 'get', 'deployments.apps/seal-agent', True),
    ('sg-vault-seal', 'get', 'deployments.apps/unrelated', False),
    ('sg-vault-seal', 'list', 'deployments.apps', False),
    ('sg-vault-seal', 'watch', 'deployments.apps/seal-agent', False),
    ('sg-vault-seal', 'patch', 'deployments.apps/seal-agent', False),
    ('sg-vault-seal', 'get', 'secrets/seal-agent-approle', False),
    ('sg-vault-seal', 'list', 'secrets', False),
    ('sg-vault-seal', 'create', 'pods/exec', False),
    ('sg-vault', 'get', 'pods/vault-0', False),
    ('sg-vault', 'get', 'secrets/vault-tls', False),
]
for namespace, verb, resource, allowed in checks:
    result = subprocess.run(['oc', '--request-timeout=10s', 'auth', 'can-i', verb, resource, '-n', namespace, '--as=system:serviceaccount:sg-app:sg-ui-observer'], capture_output=True, text=True, timeout=15)
    if result.stdout.strip() != ('yes' if allowed else 'no') or result.returncode != (0 if allowed else 1):
        raise SystemExit('Observer boundary failed: ' + verb + ' ' + resource)
Path('.build/observer-boundary.json').write_text(json.dumps({'result': 'pass', 'at': dt.datetime.now(dt.timezone.utc).isoformat(), 'checks': len(checks)}, indent=2) + '\n')
print(f'PASS: {len(checks)} actual observer RBAC permissions/denials; no Secret read, list, mutation or exec.')
PY
