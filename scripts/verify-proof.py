#!/usr/bin/env python3
"""Release gate: the protected workflow supplies provenance; verify its receipt."""
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def valid(doc, revision, digest):
    if not isinstance(doc, dict):
        return False
    if (doc.get('schemaVersion') != '1' or doc.get('scope') != 'live' or doc.get('result') != 'pass'
            or doc.get('dirty') is not False or doc.get('revision') != revision or doc.get('inputDigest') != digest
            or not doc.get('clusterId') or not doc.get('runId') or not doc.get('finishedAt')):
        return False
    spec = importlib.util.spec_from_file_location('proof_steps', ROOT / 'scripts/proof_steps.py')
    ladder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ladder)
    expected = [ladder.canonical(command) for command in ladder.commands(ROOT, True)]
    steps = doc.get('steps')
    return (isinstance(steps, list) and len(steps) == len(expected)
            and all(isinstance(step, dict) and step.get('index') == index
                    and step.get('exitCode') == 0
                    and ladder.canonical(step.get('command')) == expected[index]
                    for index, step in enumerate(steps)))


if __name__ == '__main__':
    spec = importlib.util.spec_from_file_location('input_digest', ROOT / 'scripts/input-digest.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if not valid(json.loads(Path(sys.argv[1]).read_text()), sys.argv[2], mod.digest(ROOT)):
        raise SystemExit('Release proof rejected: revision, inputs, provenance scope or required steps do not match.')
    print('Protected live proof matches this release revision and its required steps.')
