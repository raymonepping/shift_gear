"""Observe four reversible mutations; keep credentials in memory, never in logs."""
import json
import os
from pathlib import Path
import signal
import ssl
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
CONFIG = json.loads((ROOT / '.build/terraform/infra.json').read_text())['cluster']
VAULT = f"https://vault.{CONFIG['apps_domain']}"
KC = f"https://keycloak.{CONFIG['apps_domain']}"
CA = ssl.create_default_context(cafile=str(ROOT / '.secrets/tls/pub/ca.pem'))
INGRESS = ssl.create_default_context(cafile=str(ROOT / CONFIG['ingress_ca_path']))
ENV = {**os.environ, 'KUBECONFIG': str(ROOT / '.secrets/kube/config')}
MARKER = 'scenario-08-drift'
LABEL = 'shift-gear/scenario-08'


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def run(args, name, expected=0, text=None, env=None):
    r = subprocess.run(args, cwd=ROOT, env=env or ENV, input=text,
                       text=True, capture_output=True, timeout=600,
                       pass_fds=(int(os.environ["SG_LOCK_FD"]),) if os.environ.get("SG_LOCK_FD") else ())
    (ROOT / f'.cache/scenario-08-{name}.log').write_text(r.stdout + r.stderr)
    require(r.returncode == expected,
            f'{name}: expected exit {expected}, got {r.returncode}; see .cache/scenario-08-{name}.log')
    return r.stdout


def api(base, path, token=None, body=None, method='GET'):
    headers = {'X-Vault-Namespace': 'shift-gear'} if base == VAULT else {}
    if callable(token):
        token = token()
    if token:
        headers['X-Vault-Token' if base == VAULT else 'Authorization'] = token if base == VAULT else f'Bearer {token}'
    data = None
    if body is not None:
        headers['Content-Type'] = 'application/json'
        data = json.dumps(body).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(base + path, data=data, headers=headers, method=method),
                                    context=CA if base == VAULT else INGRESS, timeout=20) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raise RuntimeError(f'{method} {path}: unexpected HTTP {e.code}') from None


def tf(root, action, name, expected=0):
    args = ['./scripts/tf-run.sh', root, action, '-no-color']
    if action == 'plan':
        args.append('-detailed-exitcode')
    return run(args, name, expected)


def ldap(password, verb, ldif=''):
    # Password crosses stdin only, then a 0600 pod-local temporary file.
    script = ('umask 077; f=$(mktemp); trap \'rm -f "$f"\' EXIT; '
              'IFS= read -r password; printf "%s" "$password" > "$f"; unset password; '
              f'{verb} -H ldap://127.0.0.1:1389 -D cn=admin,dc=shiftgear,dc=local -y "$f"')
    if verb == 'ldapsearch':
        script += ' -LLL -b cn=engineers,ou=groups,dc=shiftgear,dc=local -s base member'
    return run(['oc', '-n', 'sg-identity', 'exec', '-i', 'deployment/openldap', '--', '/bin/sh', '-ec', script],
               f'ldap-{verb}', text=password + '\n' + ldif)


def ben_policies(identity):
    auth = api(VAULT, '/v1/auth/ldap/login/ben', body={'password': identity['user_ben']}, method='POST')['auth']
    token = auth['client_token']
    try:
        lookup = api(VAULT, '/v1/auth/token/lookup-self', token)
        return set(lookup['data'].get('identity_policies') or [])
    finally:
        api(VAULT, '/v1/auth/token/revoke-self', token, method='POST')


def interrupt(_signum, _frame):
    raise KeyboardInterrupt()


def main():
    signal.signal(signal.SIGTERM, interrupt)
    tt = (ROOT / '.secrets/tokens/tf-platform').read_text().strip()
    at = (ROOT / '.secrets/tokens/ansible-platform').read_text().strip()
    identity = api(VAULT, '/v1/kv/data/shift-gear/identity', at)['data']['data']
    payload = urllib.parse.urlencode({'client_id': 'admin-cli', 'grant_type': 'password', 'username': 'admin',
                                     'password': identity['keycloak_admin_password']}).encode()
    req = urllib.request.Request(KC + '/realms/master/protocol/openid-connect/token', data=payload,
                                 headers={'Content-Type': 'application/x-www-form-urlencoded'})
    def kt():
        # Admin access tokens are short lived; get a fresh one for each call.
        with urllib.request.urlopen(req, context=INGRESS, timeout=20) as r:
            return json.load(r)['access_token']
    client = api(KC, '/admin/realms/shift-gear/clients?clientId=sg-cli', kt)[0]
    require(client['publicClient'], 'sg-cli must be public')
    cp = '/admin/realms/shift-gear/clients/' + client['id']
    tp = '/v1/sys/mounts/transit/tune'
    description = api(VAULT, tp, tt)['data']['description']
    dep = json.loads(run(['oc', '-n', 'sg-workloads', 'get', 'deployment', 'workload-a', '-o', 'json'], 'before'))
    require(LABEL not in dep['metadata'].get('labels', {}), 'scenario label already exists')
    member = 'uid=ben,ou=people,dc=shiftgear,dc=local'
    require(f'member: {member}' not in ldap(identity['ldap_admin_password'], 'ldapsearch'), 'ben already belongs to engineers')
    require(ben_policies(identity) == set(), 'ben must start without a policy-bearing group')
    tf('platform', 'plan', 'platform-before')
    tf('workloads', 'plan', 'workloads-before')
    restore = []
    try:
        restore.append(lambda: api(VAULT, tp, tt, {'description': description}, 'POST'))
        api(VAULT, tp, tt, {'description': MARKER}, 'POST')
        require(api(VAULT, tp, tt)['data']['description'] == MARKER, 'mount mutation did not apply')
        plan = tf('platform', 'plan', 'mount-drift', 2)
        require('vault_mount.transit' in plan and MARKER in plan, 'plan did not identify mount description drift')
        tf('platform', 'apply', 'mount-restore')
        require(api(VAULT, tp, tt)['data']['description'] == description, 'mount description was not restored')
        restore.pop()
        print('PASS 1/4: Terraform detected and restored transit mount description', flush=True)

        restore.append(lambda: run(['oc', '-n', 'sg-workloads', 'label', 'deployment/workload-a', LABEL + '-'], 'label-cleanup'))
        run(['oc', '-n', 'sg-workloads', 'label', 'deployment/workload-a', f'{LABEL}={MARKER}'], 'label-mutate')
        plan = tf('workloads', 'plan', 'label-drift', 2)
        require('kubernetes_deployment.workload_a' in plan and LABEL in plan, 'plan did not identify workload-a label drift')
        tf('workloads', 'apply', 'label-restore')
        dep = json.loads(run(['oc', '-n', 'sg-workloads', 'get', 'deployment', 'workload-a', '-o', 'json'], 'label-restored'))
        require(LABEL not in dep['metadata'].get('labels', {}), 'workload label was not restored')
        restore.pop()
        print('PASS 2/4: Terraform detected and restored workload-a label', flush=True)

        restore.append(lambda: api(KC, cp, kt, client, 'PUT'))
        api(KC, cp, kt, {**client, 'name': MARKER}, 'PUT')
        require(api(KC, cp, kt)['name'] == MARKER, 'Keycloak mutation did not apply')
        run(['./scripts/ansible-run.sh', 'identity'], 'keycloak-check', env={**ENV, 'CHECK': '1'})
        stats = json.loads((ROOT / '.build/ansible-stats/identity.check.json').read_text())
        require(stats['changed_total'] > 0, 'check mode did not detect client drift')
        require(api(KC, cp, kt)['name'] == MARKER, 'check mode changed the client')
        run(['make', 'identity'], 'keycloak-restore')
        require(api(KC, cp, kt)['name'] == client['name'], 'identity did not restore client name')
        restore.pop()
        print('PASS 3/4: Ansible detected and restored sg-cli client name', flush=True)

        def membership(action):
            ldap(identity['ldap_admin_password'], 'ldapmodify',
                 f'dn: cn=engineers,ou=groups,dc=shiftgear,dc=local\nchangetype: modify\n{action}: member\nmember: {member}\n\n')
        restore.append(lambda: membership('delete'))
        membership('add')
        require(f'member: {member}' in ldap(identity['ldap_admin_password'], 'ldapsearch'), 'LDAP mutation did not apply')
        require(ben_policies(identity) == {'sg-engineer'}, 'ben login did not expose the added engineer policy')
        membership('delete')
        restore.pop()
        require(ben_policies(identity) == set(), 'ben policy was not restored')
        print('PASS 4/4: LDAP login detected added engineer policy; membership restored', flush=True)
        tf('platform', 'plan', 'platform-after')
        tf('workloads', 'plan', 'workloads-after')
        run(['make', 'identity-verify'], 'identity-after')
        print('Scenario 08 PASS: 4/4 mutations detected; plans and identity clean', flush=True)
    finally:
        errors = []
        for undo in reversed(restore):
            try:
                undo()
            except Exception:
                errors.append('cleanup failed; inspect scenario logs and converge the lab')
        if errors:
            raise RuntimeError('; '.join(errors))


if __name__ == '__main__':
    try:
        main()
    except (Exception, KeyboardInterrupt) as error:
        print(f'Scenario 08 FAIL: {error}', file=sys.stderr)
        sys.exit(1)
