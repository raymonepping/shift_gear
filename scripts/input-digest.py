#!/usr/bin/env python3
"""Hash relative names and bytes; never inspect generated state or credentials."""
import hashlib
from pathlib import Path
import sys


def digest(root):
    excluded = {'.terraform', 'node_modules', '.nuxt', '.output', '.cache', '.secrets', '.auth', '__pycache__', 'test-results', 'playwright-report'}
    paths = []
    for folder in ('ansible', 'terraform', 'policies', 'deploy', 'scripts', 'collector', 'ui', 'tests', 'scenarios', '.github'):
        for p in (root / folder).rglob('*'):
            if p.is_file() and not (set(p.relative_to(root).parts) & excluded) and not p.name.startswith('._') and p.name != '.DS_Store' and '.tfstate' not in p.name and p.suffix not in {'.log', '.pid', '.tmp', '.backup', '.tfplan'}:
                paths.append(p)
    paths += [root / name for name in ('Makefile', 'ansible.cfg') if (root / name).exists()]
    result = hashlib.sha256()
    for path in sorted(paths, key=lambda p: p.relative_to(root).as_posix()):
        name = path.relative_to(root).as_posix().encode()
        data = path.read_bytes()
        result.update(len(name).to_bytes(8, 'big') + name + len(data).to_bytes(8, 'big') + data)
    return result.hexdigest()


if __name__ == '__main__':
    print(digest(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]))
