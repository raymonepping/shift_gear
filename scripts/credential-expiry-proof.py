#!/usr/bin/env python3
"""Keep credential bodies in memory; publish only boolean proof results."""
import base64
import datetime as dt
import json
import os
from pathlib import Path
import ssl
import subprocess
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def main():
    domain = json.loads((ROOT / '.build/terraform/infra.json').read_text())['cluster']['apps_domain']
    token = (ROOT / '.secrets/tokens/ansible-seal').read_text().strip()
    ctx = ssl.create_default_context(cafile=str(ROOT / '.secrets/tls/pub/ca.pem'))
    base = f'https://vault-seal.{domain}/v1/auth/approle/role/sg-seal-autounseal/'

    def request(path, body):
        req = urllib.request.Request(base + path, data=json.dumps(body).encode(),
                                     headers={'X-Vault-Token': token, 'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req, context=ctx, timeout=10) as response:
                return response.status, json.load(response) if response.status == 200 else {}
        except urllib.error.HTTPError as error:
            return error.code, {}

    def current():
        obj = json.loads(subprocess.check_output(['oc', '--request-timeout=10s', '-n', 'sg-vault-seal', 'get', 'secret', 'seal-agent-approle', '-o', 'json']))
        return base64.b64decode(obj['data']['secret-id']).decode()

    def patch(value):
        subprocess.run(['oc', '--request-timeout=10s', '-n', 'sg-vault-seal', 'patch', 'secret', 'seal-agent-approle',
                        '--type=merge', '--patch-file=/dev/stdin'], input=json.dumps({'data': {'secret-id': base64.b64encode(value.encode()).decode()}}).encode(),
                       stdout=subprocess.DEVNULL, check=True)

    original = current()
    status, old = request('secret-id/lookup', {'secret_id': original})
    if status != 200:
        raise SystemExit('Original Agent credential is not valid; reconcile make agent first.')
    status, issued = request('secret-id', {'ttl': '2s', 'metadata': '{"purpose":"expiry-proof"}'})
    if status != 200:
        raise SystemExit('Could not issue the scoped expiry fixture.')
    expired = issued['data']['secret_id']
    if issued['data'].get('secret_id_ttl') != 2:
        raise SystemExit('Fixture TTL was not honored; live credential unchanged.')
    time.sleep(3)
    lookup_status, retained = request('secret-id/lookup', {'secret_id': expired})
    print('Fixture expiry metadata', {key: retained.get('data', {}).get(key) for key in ['creation_time', 'expiration_time', 'secret_id_ttl']}, 'lookup status', lookup_status)
    # AppRole lookup can retain expired metadata until tidy. A successful
    # lookup alone is not evidence that the credential can authenticate.
    def login(secret, reject):
        script = ('export VAULT_ADDR=https://vault-seal.sg-vault-seal.svc:8200 '
                  'VAULT_CACERT=/vault/userconfig/seal-agent-tls/ca.crt; '
                  'umask 077; errors=$(mktemp); trap \'rm -f "$errors"\' EXIT; '
                  'if token=$(vault write -field=token auth/approle/login role_id=@/vault/approle/role-id secret_id=- 2>"$errors"); then '
                  'VAULT_TOKEN="$token" vault token revoke -self >/dev/null; '
                  + ('exit 42; ' if reject else 'exit 0; ')
                  + 'else ' + ('grep -Eiq "invalid secret id|invalid role or secret.?id|secret.?id.*expired" "$errors"; ' if reject else 'cat "$errors" >&2; exit 43; ') + 'fi')
        result = subprocess.run(['oc', '--request-timeout=15s', '-n', 'sg-vault-seal', 'exec', '-i', 'deployment/seal-agent', '-c', 'seal-agent', '--',
                               'sh', '-ec', script], input=secret.encode(),
                              capture_output=True, timeout=20)
        if result.returncode:
            labels = [label for label in ['permission denied', 'missing', 'invalid secret id', 'Error parsing', 'flag', 'certificate', 'timeout', 'CIDR', 'No value found', 'Field', 'invalid role or secret', 'expired'] if label.lower() in result.stderr.decode(errors='replace').lower()]
            print('Login probe', 'expired' if reject else 'positive', 'exit', result.returncode, 'diagnostic classes', labels)
        return result.returncode

    expiration = retained.get('data', {}).get('expiration_time')
    if lookup_status not in (204, 404) and (lookup_status != 200 or not expiration or dt.datetime.fromisoformat(expiration.replace('Z', '+00:00')).timestamp() > time.time()):
        raise SystemExit('Fixture metadata has not expired; live credential unchanged.')
    if login(original, False) != 0:
        raise SystemExit('Positive login control failed; live credential unchanged.')
    patch(expired)
    fd = int(os.environ['SG_LOCK_FD'])
    try:
        subprocess.run(['make', 'agent'], cwd=ROOT, pass_fds=(fd,), check=True)
        replacement = current()
        if replacement == expired or request('secret-id/lookup', {'secret_id': replacement})[0] != 200 or login(replacement, False) != 0:
            raise RuntimeError('Replacement verification failed')
    except Exception:
        patch(original)
        subprocess.run(['oc', '-n', 'sg-vault-seal', 'rollout', 'restart', 'deployment/seal-agent'], check=True)
        subprocess.run(['oc', '-n', 'sg-vault-seal', 'rollout', 'status', 'deployment/seal-agent', '--timeout=180s'], check=True)
        raise SystemExit('Repair failed; original credential restored. Inspect the private proof log.') from None
    status, _ = request('secret-id-accessor/destroy', {'secret_id_accessor': old['data']['secret_id_accessor']})
    if status not in (200, 204):
        raise SystemExit('Repair passed, but previous accessor retirement failed.')
    if login(expired, True) != 0 or login(original, True) != 0:
        raise SystemExit('Repaired credentials were not fully retired.')
    print('PASS: expired metadata detected, make agent repaired and retired it, fresh login verified, predecessor reuse refused.')


if __name__ == '__main__':
    main()
