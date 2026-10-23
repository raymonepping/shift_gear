#!/usr/bin/env python3
"""Only named task events may use the evidence-publication exception."""
import json
from pathlib import Path
import sys


def allowed(doc, rules):
    if doc.get('failed_total', 1) != 0:
        return False
    if doc.get('changed_total') == 0:
        return True
    events = doc.get('changed_tasks', [])
    names = set(rules.get(doc.get('phase'), []))
    return bool(events) and len(events) == doc['changed_total'] and all(name in names for name in events)


if __name__ == '__main__':
    rules = json.loads((Path(__file__).parent / 'idempotency-tasks.json').read_text())
    sys.exit(0 if allowed(json.loads(Path(sys.argv[1]).read_text()), rules) else 1)
