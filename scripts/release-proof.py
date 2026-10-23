#!/usr/bin/env python3
"""Execute the declared ladder and emit a sanitized, revision-bound receipt."""
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys
import uuid
from proof_steps import canonical, commands as proof_commands

ROOT = Path(__file__).resolve().parents[1]


def main():
    live = '--live' in sys.argv
    ident = str(uuid.uuid4())
    logs = ROOT / '.cache/proofs' / ident
    logs.mkdir(parents=True, mode=0o700)
    commands = proof_commands(ROOT, live)
    doc = {'schemaVersion': '1', 'proofId': ident, 'scope': 'live' if live else 'offline',
           'revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
           'dirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)),
           'runtimePolicy': {'preserveSelectedRuntimes': True, 'allowConcurrentPodman': os.environ.get('ALLOW_PODMAN') == '1'},
           'startedAt': dt.datetime.now(dt.timezone.utc).isoformat(), 'steps': [],
           'recovery': 'deferred by operator', 'result': 'running'}
    digest = subprocess.check_output([str(ROOT / 'scripts/automation-digest.sh')], text=True).strip()
    doc['inputDigest'] = digest
    output = ROOT / '.build/proof-manifest.json'
    output.parent.mkdir(exist_ok=True)
    fd = int(os.environ['SG_LOCK_FD']) if os.environ.get('SG_LOCK_FD') else None
    for index, command in enumerate(commands):
        with (logs / f'{index:02}.log').open('w') as log:
            rc = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                pass_fds=(fd,) if fd is not None else ()).returncode
        doc['steps'].append({'index': index, 'command': canonical(command), 'exitCode': rc})
        output.write_text(json.dumps(doc, indent=2) + '\n')
        print(f'{index + 1}/{len(commands)} {command[0]} {Path(command[1]).name}: {"PASS" if rc == 0 else "FAIL"}', flush=True)
        if rc:
            doc['result'] = 'fail'
            break
    else:
        final = subprocess.check_output([str(ROOT / 'scripts/automation-digest.sh')], text=True).strip()
        doc['result'] = 'pass' if final == digest else 'inputs-changed'
    doc['finishedAt'] = dt.datetime.now(dt.timezone.utc).isoformat()
    if live:
        run = json.loads((ROOT / '.build/run.json').read_text())
        doc.update(clusterId=run['clusterId'], runId=run['runId'], optionalObservability=json.loads((ROOT / '.build/terraform/workloads.json').read_text()).get('observability'))
    output.write_text(json.dumps(doc, indent=2) + '\n')
    return int(doc['result'] != 'pass')


if __name__ == '__main__':
    sys.exit(main())
