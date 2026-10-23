#!/usr/bin/env python3
"""Wait for published HA metadata after an actual unsealed Raft roll."""
import json
from pathlib import Path
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
domain = json.loads((ROOT / '.build/terraform/infra.json').read_text())['cluster']['apps_domain']
token = (ROOT / '.secrets/tokens/ansible-platform').read_text().strip()
ctx = ssl.create_default_context(cafile=str(ROOT / '.secrets/tls/pub/ca.pem'))


def get(path):
    request = urllib.request.Request(f'https://vault.{domain}/v1/{path}', headers={'X-Vault-Token': token})
    with urllib.request.urlopen(request, context=ctx, timeout=5) as response:
        return json.load(response)


unsealed = '--unsealed' in sys.argv
budget = 300 if unsealed else 60
deadline = time.monotonic() + budget
while time.monotonic() < deadline:
    try:
        if unsealed:
            statuses = [json.loads(subprocess.check_output(
                ['timeout', '8', 'oc', '--request-timeout=5s', '-n', 'sg-vault', 'exec', f'vault-{i}', '--',
                 'env', 'VAULT_ADDR=https://127.0.0.1:8200', 'vault', 'status', '-format=json'],
                stderr=subprocess.DEVNULL, timeout=10)) for i in range(3)]
            if not all(status.get('initialized') is True and status.get('sealed') is False for status in statuses):
                time.sleep(2)
                continue
        ha = get('sys/ha-status')
        raft = get('sys/storage/raft/configuration')
        active = sum(node.get('active_node') is True for node in ha.get('nodes', []))
        voters = sum(node.get('voter') is True for node in raft.get('data', {}).get('config', {}).get('servers', []))
        if active == 1 and voters == 3:
            print('HA metadata settled: one active, three Raft voters.')
            break
    except (OSError, ValueError, urllib.error.URLError, subprocess.SubprocessError):
        pass
    time.sleep(2)
else:
    raise SystemExit(f'Vault unseal/HA postconditions did not settle within {budget} seconds.')
