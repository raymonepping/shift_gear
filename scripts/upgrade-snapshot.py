#!/usr/bin/env python3
"""Protected pre-upgrade downloads of BOTH Raft stores. Never restores data."""
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import ssl
import subprocess
import time
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[1]


def main():
    os.umask(0o077)
    cluster = subprocess.check_output(['oc', '--request-timeout=5s', 'get', 'namespace', 'kube-system', '-o', 'jsonpath={.metadata.uid}'], text=True)
    domain = json.loads((ROOT / '.build/terraform/infra.json').read_text())['cluster']['apps_domain']
    context = ssl.create_default_context(cafile=str(ROOT / '.secrets/tls/pub/ca.pem'))
    target = ROOT / '.secrets/pre-upgrade' / str(uuid.uuid4())
    target.mkdir(parents=True, mode=0o700)
    manifest = {'schemaVersion': '1', 'clusterId': cluster, 'at': dt.datetime.now(dt.timezone.utc).isoformat(), 'stores': {}, 'restoreProven': False}
    for name in ['seal', 'main']:
        address = f'https://{"vault-seal" if name == "seal" else "vault"}.{domain}/v1/'
        parent = (ROOT / f'.secrets/tokens/ansible-{"seal" if name == "seal" else "platform"}').read_text().strip()
        def call(path, token, body=None):
            req = urllib.request.Request(address + path, data=None if body is None else json.dumps(body).encode(),
                headers={'X-Vault-Token': token, 'Content-Type': 'application/json'})
            return urllib.request.urlopen(req, context=context, timeout=30)
        with call('auth/token/create/sg-snapshot-reader', parent, {'policies': ['sg-snapshot-reader'], 'ttl': '120s'}) as response:
            token = json.load(response)['auth']['client_token']
        try:
            paths = ['sys/storage/raft/snapshot', 'sys/storage/raft/snapshot-force', 'sys/policies/acl/test']
            with call('sys/capabilities-self', token, {'paths': paths}) as response:
                caps = json.load(response)['data']
            if caps[paths[0]] != ['read'] or caps[paths[1]] != ['deny'] or caps[paths[2]] != ['deny']:
                raise RuntimeError('Snapshot identity permissions differ from read-only maintenance scope')
            deadline = time.monotonic() + 90
            snapshot = target / f'{name}.snap'
            with call('sys/storage/raft/snapshot', token) as response, snapshot.open('xb') as output:
                digest = hashlib.sha256()
                total = 0
                while chunk := response.read(1024 * 1024):
                    if time.monotonic() > deadline:
                        raise RuntimeError('Snapshot absolute deadline exceeded')
                    total += len(chunk)
                    if total > 1024 * 1024 * 1024:
                        raise RuntimeError('Snapshot exceeds the maintenance size budget')
                    output.write(chunk)
                    digest.update(chunk)
            if total == 0:
                raise RuntimeError('Empty snapshot refused')
            result = subprocess.run(['vault', 'operator', 'raft', 'snapshot', 'inspect', str(snapshot)], capture_output=True, timeout=30)
            if result.returncode:
                raise RuntimeError('Snapshot structural inspection failed')
            manifest['stores'][name] = {'sha256': digest.hexdigest(), 'bytes': total, 'structurallyInspected': True}
        finally:
            with call('auth/token/revoke-self', token, {}):
                pass
    manifest['result'] = 'pass'
    (target / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    # Public receipt omits snapshot content and private file names/hashes.
    (ROOT / '.build/upgrade-snapshot.json').write_text(json.dumps({'result': 'pass', 'clusterId': cluster, 'at': manifest['at'], 'storesInspected': 2, 'restoreProven': False}, indent=2) + '\n')
    print('PASS: both Raft snapshots inspected and retained privately under .secrets/pre-upgrade. Isolated restore remains deferred.')


if __name__ == '__main__':
    receipt_path = ROOT / '.build/upgrade-snapshot.json'
    receipt_path.parent.mkdir(exist_ok=True)
    initial_digest = subprocess.check_output(['python3', str(ROOT / 'scripts/input-digest.py')], text=True).strip()
    receipt_path.write_text(json.dumps({'schemaVersion': '1', 'result': 'running', 'at': dt.datetime.now(dt.timezone.utc).isoformat(), 'inputDigest': initial_digest}) + '\n')
    try:
        main()
        final_digest = subprocess.check_output(['python3', str(ROOT / 'scripts/input-digest.py')], text=True).strip()
        if final_digest != initial_digest:
            raise RuntimeError('Inputs changed during the proof; rerun on stable sources')
    except Exception:
        receipt_path.write_text(json.dumps({'schemaVersion': '1', 'result': 'fail', 'at': dt.datetime.now(dt.timezone.utc).isoformat(), 'inputDigest': initial_digest}) + '\n')
        raise SystemExit('Pre-upgrade snapshot incomplete; keep partial files private and do not start an upgrade.') from None
