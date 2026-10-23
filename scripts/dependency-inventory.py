#!/usr/bin/env python3
"""Export dependency identities and image metadata, never pod env/Secret data."""
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    os.umask(0o077)
    def command(args):
        return subprocess.check_output(args, cwd=ROOT, text=True, timeout=20)
    providers = {}
    for folder in ['infra', 'foundation', 'workloads', 'seal', 'platform']:
        lock = (ROOT / f'terraform/{folder}/.terraform.lock.hcl').read_text()
        providers[folder] = dict(re.findall(r'provider "([^"]+)" \{\s+version\s+= "([^"]+)"', lock))
    images = []
    for namespace in ['sg-vault-seal', 'sg-vault', 'sg-identity', 'sg-workloads', 'sg-app']:
        pods = json.loads(command(['oc', '--request-timeout=10s', '-n', namespace, 'get', 'pods', '-o', 'json']))
        for pod in pods['items']:
            statuses = pod.get('status', {}).get('containerStatuses', []) + pod.get('status', {}).get('initContainerStatuses', [])
            for container in pod['spec'].get('containers', []) + pod['spec'].get('initContainers', []):
                images.append({'namespace': namespace, 'kind': 'Pod', 'pod': pod['metadata']['name'], 'phase': pod['status']['phase'],
                    'historical': pod['status']['phase'] in ['Succeeded', 'Failed'], 'container': container['name'],
                    'configuredImage': container['image'], 'runtimeImageID': next((s.get('imageID') for s in statuses if s['name'] == container['name']), None),
                    'immutableReference': bool(re.search(r'@sha256:[a-f0-9]{64}$', container['image']))})
        controllers = json.loads(command(['oc', '--request-timeout=10s', '-n', namespace, 'get', 'deployments,statefulsets,cronjobs', '-o', 'json']))
        for controller in controllers['items']:
            spec = controller['spec']
            if controller['kind'] == 'CronJob':
                spec = spec['jobTemplate']['spec']
            template = spec['template']['spec']
            for container in template.get('containers', []) + template.get('initContainers', []):
                images.append({'namespace': namespace, 'kind': controller['kind'], 'resource': controller['metadata']['name'],
                    'historical': False, 'container': container['name'], 'configuredImage': container['image'], 'runtimeImageID': None,
                    'immutableReference': bool(re.search(r'@sha256:[a-f0-9]{64}$', container['image']))})
    sub = json.loads(command(['oc', '--request-timeout=10s', '-n', 'openshift-operators', 'get', 'subscription', 'vault-secrets-operator', '-o', 'json']))
    version = json.loads(command(['oc', '--request-timeout=10s', 'version', '-o', 'json']))
    result = {'schemaVersion': '1', 'at': dt.datetime.now(dt.timezone.utc).isoformat(), 'providers': providers,
              'terraform': json.loads(command(['terraform', 'version', '-json']))['terraform_version'],
              'node': command(['node', '--version']).strip(), 'openshift': version.get('openshiftVersion'),
              'architecture': version.get('serverVersion', {}).get('platform'),
              'operator': {'installedCSV': sub.get('status', {}).get('installedCSV'), 'approval': sub['spec']['installPlanApproval'], 'channel': sub['spec']['channel']},
              'images': images, 'mutableReferences': sum(not item['immutableReference'] and not item['historical'] for item in images),
              'mutableHistoricalReferences': sum(not item['immutableReference'] and item['historical'] for item in images)}
    result['result'] = 'pass' if result['mutableReferences'] == 0 else 'fail'
    (ROOT / '.build/dependency-inventory.json').write_text(json.dumps(result, indent=2) + '\n')
    if result['mutableReferences']:
        raise SystemExit('Dependency inventory rejected mutable deployed image references; inspect the private inventory.')
    print('Dependency inventory written: provider selections, operator approval and configured/runtime image identities. No credentials exported.')


if __name__ == '__main__':
    main()
