#!/usr/bin/env python3
"""Reject credential-bearing resource state. Print paths/labels, never values."""
import json
import re
import sys
from pathlib import Path

PATTERNS = [re.compile(r'hv[sbr]\.[A-Za-z0-9_-]{20,}'),
            re.compile(r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
            re.compile(r'-----BEGIN (?:[A-Z ]+)?PRIVATE KEY-----')]


def findings(document):
    hits = []
    for resource in document.get('resources', []):
        address = f"{resource.get('type')}.{resource.get('name')}"
        for instance in resource.get('instances', []):
            attrs = instance.get('attributes', {})
            for key in ('data', 'binary_data', 'data_wo'):
                data = attrs.get(key) or {}
                if isinstance(data, dict) and any(data.get(k) for k in ('token', 'password', 'secret-id', 'private_key', 'tls.key')):
                    hits.append(address + ': credential field')
            if any(pattern.search(json.dumps(attrs)) for pattern in PATTERNS):
                hits.append(address + ': credential pattern')
    return sorted(set(hits))


def main():
    files = [Path(p) for p in sys.argv[1:]]
    if not files:
        files = list((Path(__file__).resolve().parents[1] / '.secrets/terraform').glob('*/terraform.tfstate'))
    if not files:
        print('State audit incomplete: no state files', file=sys.stderr)
        return 1
    failed = False
    for path in files:
        try:
            hits = findings(json.loads(path.read_text()))
        except (OSError, ValueError):
            hits = ['unreadable or invalid state']
        for label in hits:
            print(f'STATE: {path.name}: {label}', file=sys.stderr)
        failed |= bool(hits)
    return int(failed)


if __name__ == '__main__':
    sys.exit(main())
