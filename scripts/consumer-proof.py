#!/usr/bin/env python3
"""One C03 consumer: real DB isolation, token isolation, expiry and restart recovery."""
import datetime as dt
import json
import re
import ssl
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / '.build/consumer-proof.json'
CTX = None
DOMAIN = None


def oc(*args, timeout=200):
    return subprocess.run(['oc', '--request-timeout=180s', *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout)


def output(*args, timeout=200):
    result = oc(*args, timeout=timeout)
    if result.returncode: raise RuntimeError('Consumer proof command incomplete; inspect fixture readiness')
    return result.stdout.strip()


def vault(path, token=None, body=None):
    headers = {'X-Vault-Namespace': 'shift-gear'}
    if token: headers['X-Vault-Token'] = token
    if body is not None: headers['Content-Type'] = 'application/json'
    request = urllib.request.Request(f'https://vault.{DOMAIN}/v1/{path}', data=json.dumps(body).encode() if body is not None else None, headers=headers)
    try:
        with urllib.request.urlopen(request, context=CTX, timeout=10) as response:
            raw = response.read(65536); return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        return error.code, {}


def main(checks, tokens):
    global CTX, DOMAIN
    CTX = ssl.create_default_context(cafile=str(ROOT / ".secrets/tls/pub/ca.pem"))
    DOMAIN = json.loads((ROOT / ".build/terraform/infra.json").read_text())["cluster"]["apps_domain"]
    def check(name, condition):
        if not condition: raise RuntimeError('Consumer proof failed: ' + name)
        checks[name] = True
    def consumer(command):
        return oc('-n', 'sg-workloads', 'exec', 'deployment/sg-agent-db', '-c', 'consumer', '--', 'sh', '-c', command, timeout=20)
    def user():
        result = consumer('cut -d: -f4 /vault/secrets/pgpass')
        if result.returncode or not re.fullmatch(r'[A-Za-z0-9_-]{1,100}', result.stdout.strip()): raise RuntimeError('Invalid fixture principal metadata')
        return result.stdout.strip()
    def query(sql):
        return consumer("export PGHOST=postgres.sg-workloads.svc PGDATABASE=shiftgear PGPASSFILE=/vault/secrets/pgpass PGCONNECT_TIMEOUT=2; export PGUSER=$(cut -d: -f4 /vault/secrets/pgpass); psql -X -w -tAc '" + sql + "'")
    def role_exists(name):
        result = oc('-n', 'sg-workloads', 'exec', 'deployment/postgres', '--', 'psql', '-U', 'postgres', '-d', 'shiftgear', '-tAc', "SELECT count(*) FROM pg_roles WHERE rolname='" + name + "'", timeout=20)
        if result.returncode: raise RuntimeError('Cannot verify fixture principal retirement')
        return result.stdout.strip() != '0'
    output('-n', 'sg-workloads', 'rollout', 'status', 'deployment/sg-agent-db', '--timeout=180s')
    result = query('SELECT COUNT(*) FROM sg_agent.canary')
    check('actual isolated database read', result.returncode == 0 and result.stdout.strip() == '1')
    result = query('SELECT COUNT(*) FROM public.demo')
    check('existing application table denied', result.returncode != 0 and 'permission denied' in result.stderr.lower())
    result = consumer('test ! -e /var/run/sg-agent/token && test ! -e /var/run/secrets/kubernetes.io/serviceaccount/token && test ! -e /vault/token/.token && test "$(stat -c %a /vault/secrets/pgpass)" = 600')
    check('application cannot read JWT or Vault token and credentials are mode 600', result.returncode == 0)
    pods = json.loads(output('-n', 'sg-workloads', 'get', 'pods', '-l', 'app.kubernetes.io/name=sg-agent-db', '-o', 'json'))['items']
    active = [item for item in pods if not item['metadata'].get('deletionTimestamp')]
    check('single active consumer pod', len(active) == 1)
    pod = active[0]
    app = next(item for item in pod['spec']['containers'] if item['name'] == 'consumer')
    check('memory delivery without Kubernetes Secret or automatic token mount', pod['spec'].get('automountServiceAccountToken') is False
          and all(item['name'] in ('config', 'credentials', 'health') for item in app.get('volumeMounts', []))
          and not any('secret' in volume for volume in pod['spec']['volumes'])
          and next(volume for volume in pod['spec']['volumes'] if volume['name'] == 'credentials')['emptyDir']['medium'] == 'Memory')
    def login(account, role, audience=None):
        args = ['-n', 'sg-workloads', 'create', 'token', account, '--duration=10m']
        if audience: args.append('--audience=' + audience)
        jwt = output(*args, timeout=20)
        status, data = vault('auth/kubernetes/login', body={'role': role, 'jwt': jwt})
        token = data.get('auth', {}).get('client_token')
        if token: tokens.append(token)
        return status, token
    status, agent = login('sg-agent-db', 'sg-agent-db', 'vault')
    check('fresh namespace and audience bound Agent authentication', status == 200 and bool(agent))
    check('own dynamic credential path allowed', vault('database/creds/agent-reader', agent)[0] == 200)
    check('VSO credential and application KV denied', vault('database/creds/demo-reader', agent)[0] == 403 and vault('kv/data/shift-gear/config/app-config', agent)[0] == 403)
    check('wrong service account refused', login('vso-workloads', 'sg-agent-db', 'vault')[0] == 403)
    status, vso = login('vso-workloads', 'vso-workloads')
    check('VSO identity cannot read Agent role', status == 200 and bool(vso) and vault('database/creds/agent-reader', vso)[0] == 403)
    old_user = user(); deadline = time.monotonic() + 180
    while time.monotonic() < deadline and user() == old_user: time.sleep(3)
    check('Agent replaces its short-lived credential without a rollout', user() != old_user)
    # Replacement can precede expiry. Bound retirement by the configured 120s
    # maximum lease plus 30s revocation grace, not time since file replacement.
    deadline = time.monotonic() + 150
    while time.monotonic() < deadline and role_exists(old_user): time.sleep(3)
    check('superseded principal retires within maximum lease plus revocation grace', not role_exists(old_user))
    check('consumer reads after credential replacement', query('SELECT COUNT(*) FROM sg_agent.canary').stdout.strip() == '1')
    previous_user = user(); old_uid = pod['metadata']['uid']
    output('-n', 'sg-workloads', 'delete', 'pod', pod['metadata']['name'], '--wait=true', '--timeout=60s')
    output('-n', 'sg-workloads', 'rollout', 'status', 'deployment/sg-agent-db', '--timeout=180s')
    pods = json.loads(output('-n', 'sg-workloads', 'get', 'pods', '-l', 'app.kubernetes.io/name=sg-agent-db', '-o', 'json'))['items']
    check('actual restart reacquires independent credentials and query access', any(item['metadata']['uid'] != old_uid for item in pods)
          and user() != previous_user and query('SELECT COUNT(*) FROM sg_agent.canary').stdout.strip() == '1')
    deadline = time.monotonic() + 150
    while time.monotonic() < deadline and role_exists(previous_user): time.sleep(3)
    check('pre-restart principal retires within bounded lease lifetime', not role_exists(previous_user))


if __name__ == '__main__':
    digest = subprocess.check_output([str(ROOT / 'scripts/automation-digest.sh')], text=True).strip()
    receipt = {'schemaVersion': '1', 'result': 'running', 'inputDigest': digest, 'at': dt.datetime.now(dt.timezone.utc).isoformat()}
    OUTPUT.parent.mkdir(exist_ok=True)
    OUTPUT.write_text(json.dumps(receipt, indent=2) + '\n')
    checks, tokens, failure = {}, [], None
    try: main(checks, tokens)
    except Exception as error: failure = str(error) if isinstance(error, RuntimeError) else 'Consumer proof incomplete; inspect fixture readiness'
    finally:
        for token in tokens:
            try:
                status, _ = vault('auth/token/revoke-self', token, {})
                if status not in (200, 204) and vault('auth/token/lookup-self', token)[0] != 403: failure = 'Consumer proof identity cleanup failed'
            except Exception: failure = 'Consumer proof identity cleanup incomplete'
    if subprocess.check_output([str(ROOT / 'scripts/automation-digest.sh')], text=True).strip() != digest: failure = 'Inputs changed during consumer proof'
    receipt.update(result='fail' if failure else 'pass', at=dt.datetime.now(dt.timezone.utc).isoformat(), checks=checks)
    OUTPUT.write_text(json.dumps(receipt, indent=2) + '\n')
    if failure: raise SystemExit(failure)
    print(f'PASS: {len(checks)} C03 actual isolation, expiry, file delivery and restart checks. No credential values exported.')
