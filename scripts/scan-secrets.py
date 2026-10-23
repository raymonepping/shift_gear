#!/usr/bin/env python3
"""Coverage-aware scan. Diagnostics contain labels and filenames, never values."""
import datetime as dt
import importlib.util
import json
import os
from pathlib import Path
import re
import ssl
import subprocess
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SECRETS = ROOT / '.secrets'


def credential_values(path, data):
    # This seed field is a public application identifier, also used in labels
    # and validation prose. All other/new fields remain secret by default.
    public_fields = {'shift-gear/config/app-config': {'app_name': 'shift-gear'},
                     'shift-gear/agent/demo-secret': {'demo_feature_flag': 'agent-sidecar-demo'}}
    def public(key, value):
        if value == public_fields.get(path, {}).get(key):
            return True
        if path != 'shift-gear/config/app-config':
            return False
        # These are the action's deliberately public correlation metadata,
        # never its session_secret. Unexpected values remain scan sources.
        if key == 'rotation_id':
            return bool(re.fullmatch(r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}', value, re.I))
        if key == 'rotated_at' and re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z', value):
            try:
                dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
                return True
            except ValueError:
                pass
        return False
    return [value.encode() for key, value in data.items()
            if isinstance(value, str) and not public(key, value)]


def patterns():
    return [re.compile(rb'hv[sbr]\.[A-Za-z0-9_-]{20,}'),
            re.compile(rb'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
            re.compile(rb'-----BEGIN [A-Z ]*PRIVATE KEY-----\s+[A-Za-z0-9+/=]{40}'),
            re.compile(rb'02MV4UU43BK[5]')]


def main():
    values, coverage, errors = [], {}, []
    for path in (SECRETS / 'tokens').glob('*'):
        if path.is_file():
            values.append(path.read_bytes().strip())
    for name in ('seal-init', 'vault-init'):
        path = SECRETS / f'{name}.json'
        if path.exists():
            doc = json.loads(path.read_text())
            values.append(str(doc.get('root_token', '')).encode())
            for key, value in doc.items():
                if 'key' in key and isinstance(value, list):
                    values.extend(str(v).encode() for v in value)
    for path in (SECRETS / 'tls').glob('*.key'):
        values.extend(path.read_bytes().splitlines()[1:2])
    if os.environ.get('VAULT_LICENSE'):
        values.append(os.environ['VAULT_LICENSE'][:64].encode())
    if os.environ.get('SG_SCAN_MODE') != 'offline':
        try:
            result = subprocess.run(['oc', '--request-timeout=5s', '-n', 'sg-vault-seal', 'get', 'secret',
                                     'seal-agent-approle', 'seal-rotator-approle', '-o', 'json'],
                                    capture_output=True, timeout=15, check=True)
            import base64
            for item in json.loads(result.stdout)['items']:
                values.extend(base64.b64decode(v) for k, v in item.get('data', {}).items() if 'secret' in k)
            coverage['approle'] = 'complete'
        except (OSError, ValueError, subprocess.SubprocessError):
            errors.append('required AppRole source unavailable')
            coverage['approle'] = 'incomplete'
        try:
            domain = json.loads((ROOT / '.build/terraform/infra.json').read_text())['cluster']['apps_domain']
            token = (SECRETS / 'tokens/ansible-platform').read_text().strip()
            ctx = ssl.create_default_context(cafile=str(SECRETS / 'tls/pub/ca.pem'))

            def request(path, method='GET'):
                req = urllib.request.Request(f'https://vault.{domain}/v1/kv/{path}', method=method,
                                             headers={'X-Vault-Token': token, 'X-Vault-Namespace': 'shift-gear'})
                with urllib.request.urlopen(req, context=ctx, timeout=10) as response:
                    return json.load(response)['data']

            def walk(prefix):
                for key in request('metadata/' + prefix, 'LIST')['keys']:
                    if key.endswith('/'):
                        walk(prefix + key)
                    else:
                        data = request('data/' + prefix + key)['data']
                        values.extend(credential_values(prefix + key, data))
            walk('shift-gear/')
            coverage['kv'] = 'complete'
        except (OSError, ValueError, KeyError):
            errors.append('required recursive KV source unavailable')
            coverage['kv'] = 'incomplete'
    else:
        coverage['live_sources'] = 'explicitly skipped: offline scope only'

    if len(sys.argv) > 1:
        targets = [Path(name) for name in sys.argv[1:]]
    else:
        result = subprocess.run(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'],
                                cwd=ROOT, capture_output=True, check=True)
        targets = [ROOT / os.fsdecode(p) for p in result.stdout.split(b'\0') if p]
        targets += list((ROOT / '.build').rglob('*'))
        targets += list((ROOT / '.cache').rglob('*.log'))
        targets += list((SECRETS / 'terraform').glob('*/terraform.tfstate'))
    files = set()
    for path in targets:
        if not path.exists():
            errors.append('missing scan target: ' + path.name)
        elif path.is_dir():
            files.update(p for p in path.rglob('*') if p.is_file())
        else:
            files.add(path)
    values = [value for value in values if len(value) >= 8]
    for path in sorted(files):
        try:
            data = path.read_bytes()
            if any(value in data for value in values) or any(pattern.search(data) for pattern in patterns()):
                errors.append('secret-shaped content: ' + str(path.relative_to(ROOT) if path.is_relative_to(ROOT) else path.name))
        except OSError:
            errors.append('unreadable target: ' + path.name)
    state_files = list((SECRETS / 'terraform').glob('*/terraform.tfstate'))
    spec = importlib.util.spec_from_file_location('state_audit', ROOT / 'scripts/state-audit.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    for path in state_files:
        if path.stat().st_mode & 0o077:
            errors.append('state permission: ' + path.parent.name)
        if module.findings(json.loads(path.read_text())):
            errors.append('credential-bearing state: ' + path.parent.name)
    # Historical state is confidential recovery material, not a deliverable.
    # Preserve it under custody; do not claim it is credential-free or erase it.
    historical = list((SECRETS / 'archive').rglob('*.tfstate*')) + list((SECRETS / 'terraform').glob('*/*.backup'))
    for path in historical:
        if path.stat().st_mode & 0o077:
            errors.append('historical state permission: ' + path.name)
    doc = {'gate': 'secret-scan', 'result': 'fail' if errors else 'pass', 'hits': len(errors),
           'scope': 'offline' if os.environ.get('SG_SCAN_MODE') == 'offline' else 'live',
           'known_values': len(values), 'targets': len(files), 'source_coverage': coverage,
           'confidential_historical_states': len(historical),
           'run_id': os.environ.get('SG_RUN_ID'), 'cluster_id': os.environ.get('SG_CLUSTER_ID'),
           'at': dt.datetime.now(dt.timezone.utc).isoformat()}
    output = ROOT / ('.build/gates/evidence-scan.json' if len(sys.argv) > 1 else '.build/gates/secret-scan.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    tmp = output.with_suffix('.tmp')
    tmp.write_text(json.dumps(doc, indent=2) + '\n')
    tmp.replace(output)
    for error in errors:
        print('SCAN: ' + error, file=sys.stderr)
    print(f'Secret scan {doc["result"]}: {len(files)} files; scope={doc["scope"]}; historical state remains confidential')
    return bool(errors)


if __name__ == '__main__':
    sys.exit(main())
