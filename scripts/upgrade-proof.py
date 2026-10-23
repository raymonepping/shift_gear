#!/usr/bin/env python3
"""Collector runtime Node 22 -> 24 upgrade, config rollback, re-upgrade and audit delivery.

This does not downgrade Vault or restore incompatible persistent data.
"""
import datetime as dt
import json
import os
from pathlib import Path
import ssl
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
OLD = 'registry.access.redhat.com/ubi9/nodejs-22-minimal@sha256:03b7dd64cafaaca5019c4cc1c36e05140b1650dab6cd5c4ab1fde9d88c0537ca'


def main():
    fd = int(os.environ['SG_LOCK_FD'])
    def make(target, image=None):
        env = os.environ.copy()
        env.pop('TF_VAR_collector_image', None)
        if image:
            env['TF_VAR_collector_image'] = image
        subprocess.run(['make', target], cwd=ROOT, env=env, pass_fds=(fd,), check=True)
    def stats():
        script = "fetch('http://127.0.0.1:8080/audit?limit=0').then(r=>{if(!r.ok)throw Error();return r.json()}).then(x=>console.log(JSON.stringify(x.collector))).catch(()=>process.exit(1))"
        return json.loads(subprocess.check_output(['oc', '--request-timeout=10s', '-n', 'sg-app', 'exec', 'deployment/sg-audit', '--', 'node', '-e', script], timeout=15))
    def ready():
        subprocess.run(['oc', '--request-timeout=130s', '-n', 'sg-app', 'rollout', 'status', 'deployment/sg-audit', '--timeout=120s'], check=True, timeout=140)
        baseline = stats()
        domain = json.loads((ROOT / '.build/terraform/infra.json').read_text())['cluster']['apps_domain']
        token = (ROOT / '.secrets/tokens/ansible-platform').read_text().strip()
        context = ssl.create_default_context(cafile=str(ROOT / '.secrets/tls/pub/ca.pem'))
        for _ in range(15):
            req = urllib.request.Request(f'https://vault.{domain}/v1/auth/token/lookup-self', headers={'X-Vault-Token': token})
            with urllib.request.urlopen(req, context=context, timeout=5):
                pass
            current = stats()
            if current['listening'] and current['connections'] > 0 and current['received'] > baseline['received']:
                return current['instanceId']
            time.sleep(2)
        raise RuntimeError('Audited requests did not reach the replacement collector')
    # Mandatory fresh private snapshots; receipt never implies isolated recovery.
    make('upgrade-snapshot')
    make('workloads', OLD)
    old_instance = ready()
    try:
        make('workloads')
        upgraded_instance = ready()
        if upgraded_instance == old_instance:
            raise RuntimeError('Upgrade did not replace the collector')
        make('workloads', OLD)
        rolled_back_instance = ready()
        if rolled_back_instance == upgraded_instance:
            raise RuntimeError('Rollback did not replace the collector')
        make('workloads')
        final_instance = ready()
        if final_instance == rolled_back_instance:
            raise RuntimeError('Final upgrade did not replace the collector')
    except Exception:
        make('workloads', OLD)
        ready()
        raise RuntimeError('Upgrade proof failed; previous Node 22 collector restored. Inspect private logs.') from None
    receipt = {'schemaVersion': '1', 'result': 'pass', 'at': dt.datetime.now(dt.timezone.utc).isoformat(),
               'component': 'audit collector runtime Node 22 -> 24; unchanged metadata format', 'snapshotStores': 2,
               'configRollbackAndAuditRecovery': True, 'isolatedDataRestore': 'deferred by owner',
               'inputDigest': subprocess.check_output(['python3', 'scripts/input-digest.py'], cwd=ROOT, text=True).strip()}
    (ROOT / '.build/upgrade-proof.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print('PASS: runtime upgrade, config rollback with audit recovery, and final upgrade. No persistent-data downgrade/restore performed.')


if __name__ == '__main__':
    receipt_path = ROOT / '.build/upgrade-proof.json'
    receipt_path.parent.mkdir(exist_ok=True)
    initial_digest = subprocess.check_output(['python3', str(ROOT / 'scripts/input-digest.py')], text=True).strip()
    receipt_path.write_text(json.dumps({'schemaVersion': '1', 'result': 'running', 'at': dt.datetime.now(dt.timezone.utc).isoformat(), 'inputDigest': initial_digest}) + '\n')
    try:
        main()
        final_digest = subprocess.check_output(['python3', str(ROOT / 'scripts/input-digest.py')], text=True).strip()
        if final_digest != initial_digest:
            raise RuntimeError('Inputs changed during the proof; rerun on stable sources')
    except Exception as error:
        receipt_path.write_text(json.dumps({'schemaVersion': '1', 'result': 'fail', 'at': dt.datetime.now(dt.timezone.utc).isoformat(), 'inputDigest': initial_digest}) + '\n')
        raise SystemExit(str(error) if isinstance(error, RuntimeError) else 'Upgrade proof incomplete; inspect the private log and current collector readiness.') from None
