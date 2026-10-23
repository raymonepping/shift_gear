"""One ordered acceptance contract shared by execution and release verification."""
from pathlib import Path

SCENARIOS = ['01_kill_active', '02_restart_seal_agent', '03_rotation_proof',
             '04_seal_vault_restart', '06_static_secret_rotation', '07_dynamic_credential_revoked',
             '08_drift_detection', '09_vso_overwrites_hand_edit', '05_cold_start']


def commands(root, live):
    result = [['make', name] for name in ['check', 'must-test', 'ui-check']]
    if live:
        result += [['make', name] for name in ['credential-expiry-proof', 'certificate-proof', 'component-proof',
                   'observer-boundary', 'destruction-guard-proof', 'upgrade-proof', 'observability-proof', 'consumer-proof', 'lab', 'lab', 'drift', 'verify',
                   'boundary', 'identity-verify', 'ui-test', 'ui-test-failover', 'verify', 'drift', 'ui-screens']]
        for scenario in SCENARIOS:
            result += [['bash', str(Path(root) / 'scenarios' / scenario / 'run.sh')], ['make', 'verify']]
        result += [['make', name] for name in ['lab', 'drift', 'dependency-inventory']]
    return result


def canonical(command):
    if not isinstance(command, list) or len(command) != 2 or not all(isinstance(item, str) for item in command):
        return None
    if command[0] == 'bash':
        return ['bash', '/'.join(Path(command[1]).parts[-3:])]
    return command
