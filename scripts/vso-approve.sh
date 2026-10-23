#!/usr/bin/env bash
# Explicit, UID-bound approval; never approves an unknown catalog update.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
sg_lock "$@"
require_kubeconfig
: "${VSO_APPROVE_CSV:?Set VSO_APPROVE_CSV to the exact reviewed CSV name}"
export VSO_APPROVE_CSV
python3 - <<'PY'
import json
import os
import subprocess

def get(kind, name):
    return json.loads(subprocess.check_output(['oc', '--request-timeout=10s', '-n', 'openshift-operators', 'get', kind, name, '-o', 'json']))

sub = get('subscription', 'vault-secrets-operator')
if sub['spec']['installPlanApproval'] != 'Manual':
    raise SystemExit('Subscription is not under manual approval.')
ref = sub.get('status', {}).get('installPlanRef', {})
if not ref.get('name') or ref.get('namespace') != 'openshift-operators':
    raise SystemExit('No same-namespace install plan is referenced.')
plan = get('installplan', ref['name'])
if plan['metadata']['uid'] != ref.get('uid') or plan['spec'].get('clusterServiceVersionNames') != [os.environ['VSO_APPROVE_CSV']]:
    raise SystemExit('Install plan identity or CSV differs from the explicit selection.')
if not any(owner.get('uid') == sub['metadata']['uid'] for owner in plan['metadata'].get('ownerReferences', [])):
    raise SystemExit('Install plan does not belong to this subscription.')
patch = [{'op': 'test', 'path': '/metadata/uid', 'value': plan['metadata']['uid']},
         {'op': 'test', 'path': '/spec/clusterServiceVersionNames', 'value': [os.environ['VSO_APPROVE_CSV']]},
         {'op': 'add', 'path': '/spec/approved', 'value': True}]
subprocess.run(['oc', '--request-timeout=10s', '-n', 'openshift-operators', 'patch', 'installplan', ref['name'], '--type=json', '--patch-file=/dev/stdin'], input=json.dumps(patch).encode(), check=True)
PY
