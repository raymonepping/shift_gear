#!/usr/bin/env python3
"""Publish a built digest as Terraform input and reconcile that exact image field."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TARGETS = {'ui': ('sg-app', 'shift-gear-ui', 'sg-ui', 'ui_image'), 'ldap': ('sg-identity', 'openldap', 'openldap', 'openldap_image')}


def valid_catalog(value):
    return isinstance(value, dict) and all(key in {'ui_image', 'openldap_image'} and isinstance(image, str)
        and re.fullmatch(r'image-registry\.openshift-image-registry\.svc:5000/(sg-app/shift-gear-ui|sg-identity/openldap)@sha256:[a-f0-9]{64}', image)
        and ('/sg-app/' in image) == (key == 'ui_image') for key, image in value.items())


def main():
    namespace, stream, deployment, variable = TARGETS[sys.argv[1]]
    def get(kind, name):
        return json.loads(subprocess.check_output(['oc', '--request-timeout=10s', '-n', namespace, 'get', kind, name, '-o', 'json']))
    image_stream = get('imagestream', stream)
    tags = image_stream.get('status', {}).get('tags', [])
    items = next((tag.get('items', []) for tag in tags if tag['tag'] == 'latest'), [])
    if not items:
        raise SystemExit('Built image digest is unavailable; run the normal image build first.')
    image = items[0]['dockerImageReference']
    desired = get('deployment', deployment)
    containers = desired['spec']['template']['spec']['containers']
    index = next(i for i, container in enumerate(containers) if container['name'] == ('ui' if variable == 'ui_image' else 'openldap'))
    path = ROOT / '.secrets/deployment-images.tfvars.json'
    catalog = json.loads(path.read_text()) if path.exists() else {}
    if not valid_catalog(catalog) or not valid_catalog({variable: image}):
        raise SystemExit('Unreviewed built-image catalog shape or registry refused.')
    changed = containers[index]['image'] != image or catalog.get(variable) != image
    if changed and '--check' not in sys.argv:
        os.umask(0o077)
        catalog[variable] = image
        temp = path.with_suffix('.tmp')
        temp.write_text(json.dumps(catalog, indent=2) + '\n')
        temp.replace(path)
        patch = [{'op': 'test', 'path': '/metadata/resourceVersion', 'value': desired['metadata']['resourceVersion']},
                 {'op': 'replace', 'path': f'/spec/template/spec/containers/{index}/image', 'value': image}]
        subprocess.run(['oc', '--request-timeout=10s', '-n', namespace, 'patch', 'deployment', deployment, '--type=json', '--patch-file=/dev/stdin'], input=json.dumps(patch).encode(), stdout=subprocess.DEVNULL, check=True)
    if '--check' not in sys.argv:
        subprocess.run(['oc', '--request-timeout=190s', '-n', namespace, 'rollout', 'status', 'deployment/' + deployment, '--timeout=180s'], check=True, timeout=200, stdout=subprocess.DEVNULL)
    print('changed' if changed else 'unchanged')


if __name__ == '__main__':
    main()
