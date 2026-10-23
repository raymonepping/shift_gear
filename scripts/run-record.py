#!/usr/bin/env python3
"""Safe, atomic run manifest. No command output or credential values."""
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build'


def save(doc):
    BUILD.mkdir(exist_ok=True)
    tmp = BUILD / 'run.json.tmp'
    tmp.write_text(json.dumps(doc, indent=2) + '\n')
    tmp.replace(BUILD / 'run.json')


def main():
    action = sys.argv[1]
    now = dt.datetime.now(dt.timezone.utc).isoformat()
    if action == 'publish-status':
        doc = json.loads((BUILD / 'run.json').read_text())
        return subprocess.run(['oc', '--request-timeout=10s', '-n', 'sg-app', 'patch', 'configmap', 'sg-evidence',
                               '--type=merge', '-p', json.dumps({'data': {'run.json': json.dumps(doc)}})],
                              stdout=subprocess.DEVNULL).returncode
    if action == 'start':
        cluster = subprocess.check_output(['oc', '--request-timeout=5s', 'get', 'namespace', 'kube-system', '-o', 'jsonpath={.metadata.uid}'], text=True)
        if not cluster:
            raise SystemExit('Cannot identify target cluster')
        doc = {'schemaVersion': '1', 'runId': str(uuid.uuid4()), 'clusterId': cluster,
               'startedAt': now, 'provisioning': 'running', 'publication': 'pending', 'steps': {},
               'inputDigest': subprocess.check_output([str(ROOT / 'scripts/automation-digest.sh')], text=True).strip(),
               'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
               'dirty': bool(subprocess.check_output(['git', 'status', '--porcelain']))}
        save(doc)
        print(doc['runId'])
        return
    doc = json.loads((BUILD / 'run.json').read_text())
    if doc['runId'] != os.environ.get('SG_RUN_ID'):
        raise SystemExit('Run identity mismatch')
    if action == 'step':
        doc['steps'][sys.argv[2]] = {'status': sys.argv[3], 'at': now}
    else:
        doc[action] = sys.argv[2]
        if sys.argv[2] == 'failed':
            for step in doc['steps'].values():
                if step['status'] == 'running':
                    step['status'] = 'failed'
        doc['updatedAt'] = now
    save(doc)


if __name__ == '__main__':
    sys.exit(main())
