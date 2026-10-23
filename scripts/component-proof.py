#!/usr/bin/env python3
"""Dedicated PKI/Transit fixtures; values stay in memory, receipt is boolean only."""
import base64
import datetime as dt
import json
from pathlib import Path
import secrets
import ssl
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def main():
    domain = json.loads((ROOT / '.build/terraform/infra.json').read_text())['cluster']['apps_domain']
    context = ssl.create_default_context(cafile=str(ROOT / '.secrets/tls/pub/ca.pem'))
    base = f'https://vault.{domain}/v1/'
    parent = (ROOT / '.secrets/tokens/ansible-platform').read_text().strip()
    checks = {}

    def call(path, body=None, token=None, namespace="shift-gear"):
        req = urllib.request.Request(base + path, data=None if body is None else json.dumps(body).encode(),
            headers={'X-Vault-Namespace': namespace, 'X-Vault-Token': token or '', 'Content-Type': 'application/json'})
        try:
            with urllib.request.urlopen(req, context=context, timeout=10) as response:
                return response.status, json.load(response) if response.status == 200 else {}
        except urllib.error.HTTPError as error:
            return error.code, {}

    def expect(label, condition):
        if not condition:
            raise RuntimeError(f'Component proof failed: {label}')
        checks[label] = True
        print(f'PASS {label}', flush=True)

    code, issued = call('auth/token/create/sg-component-proof', {'policies': ['sg-component-proof'], 'ttl': '5m'}, parent, namespace='')
    expect('scoped identity issued', code == 200)
    token = issued['auth']['client_token']
    certificates = []
    try:
        plain = base64.b64encode(secrets.token_bytes(32)).decode()
        code, encrypted = call('transit/encrypt/sg-component-proof', {'plaintext': plain}, token)
        expect('encrypt', code == 200)
        old = encrypted['data']['ciphertext']
        code, decrypted = call('transit/decrypt/sg-component-proof', {'ciphertext': old}, token)
        expect('decrypt', code == 200 and decrypted['data']['plaintext'] == plain)
        rotate_status, _ = call('transit/keys/sg-component-proof/rotate', {}, token)
        expect(f'rotate dedicated key (HTTP {rotate_status})', rotate_status in (200, 204))
        code, wrapped = call('transit/rewrap/sg-component-proof', {'ciphertext': old}, token)
        expect('rewrap uses newer version', code == 200 and int(wrapped['data']['ciphertext'].split(':')[1][1:]) > int(old.split(':')[1][1:]))
        for label, ciphertext in [('old ciphertext retained', old), ('rewrapped ciphertext retained', wrapped['data']['ciphertext'])]:
            code, decrypted = call('transit/decrypt/sg-component-proof', {'ciphertext': ciphertext}, token)
            expect(label, code == 200 and decrypted['data']['plaintext'] == plain)
        expect('application key refused', call('transit/encrypt/app-data', {'plaintext': plain}, token)[0] == 403)
        expect('key deletion refused', call('transit/keys/sg-component-proof/config', {'deletion_allowed': True}, token)[0] == 403)
        expect('wrong certificate name refused', call('pki-int/issue/sg-component-proof', {'common_name': 'outside.example', 'ttl': '60s'}, token)[0] == 400)
        expect('other issuance policy refused', call('pki-int/issue/internal-client', {'common_name': 'proof.sg-workloads.svc.cluster.local'}, token)[0] == 403)
        for ttl in ['60s', '5s']:
            code, cert = call('pki-int/issue/sg-component-proof', {'common_name': 'proof.sg-workloads.svc.cluster.local', 'ttl': ttl}, token)
            expect(f'issue {ttl}', code == 200)
            certificates.append(cert['data'])
        cert, expiring = certificates
        # Only public certificate material is written; generated keys remain in memory.
        with tempfile.TemporaryDirectory(prefix='sg-pki-proof-', dir=ROOT / '.cache') as folder:
            files = Path(folder)
            (files / 'root.pem').write_text(cert['ca_chain'][-1])
            (files / 'intermediate.pem').write_text(cert['issuing_ca'])
            (files / 'leaf.pem').write_text(cert['certificate'])
            args = ['openssl', 'verify', '-CAfile', str(files / 'root.pem'), '-untrusted', str(files / 'intermediate.pem'), '-purpose', 'sslclient']
            expect('client chain verified', subprocess.run(args + [str(files / 'leaf.pem')], capture_output=True, timeout=10).returncode == 0)
            code, revoked = call('pki-int/revoke-with-key', {'certificate': cert['certificate'], 'private_key': cert['private_key']}, token)
            expect('certificate revoked with possession', code == 200 and revoked['data']['revocation_time'] > 0)
            code, crl = call('pki-int/cert/crl')
            expect('CRL readable', code == 200)
            (files / 'crl.pem').write_text(crl['data']['certificate'])
            result = subprocess.run(args + ['-crl_check', '-CRLfile', str(files / 'crl.pem'), str(files / 'leaf.pem')], capture_output=True, timeout=10)
            expect('revoked certificate rejected', result.returncode != 0 and b'certificate revoked' in result.stderr)
            time.sleep(max(0, min(7, expiring['expiration'] - time.time() + 1)))
            result = subprocess.run(['openssl', 'x509', '-noout', '-checkend', '0'], input=expiring['certificate'].encode(), capture_output=True, timeout=10)
            expect('short certificate expired', result.returncode == 1)
        receipt = {'schemaVersion': '1', 'result': 'pass', 'at': dt.datetime.now(dt.timezone.utc).isoformat(), 'checks': checks,
                   'inputDigest': subprocess.check_output(['python3', str(ROOT / 'scripts/input-digest.py')], text=True).strip()}
    finally:
        # Revocation records/old key versions are intentional retained history;
        # never delete a key or raise the minimum decryption version to clean up a proof.
        for cert in certificates:
            call('pki-int/revoke-with-key', {'certificate': cert['certificate'], 'private_key': cert['private_key']}, token)
        if call('auth/token/revoke-self', {}, token, namespace='')[0] not in (200, 204):
            raise RuntimeError('Proof token cleanup failed; token expires within five minutes')
    (ROOT / '.build/component-proof.json').write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    receipt_path = ROOT / '.build/component-proof.json'
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
        # Do not expose response bodies, tokens or generated key material in traces.
        raise SystemExit(str(error) if isinstance(error, RuntimeError) else 'Component proof failed; inspect service readiness and scoped permissions.') from None
