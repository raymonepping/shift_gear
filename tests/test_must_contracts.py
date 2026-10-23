"""Behavioral regressions for the security and run contracts (no live cluster)."""
import importlib.util
import contextlib
import io
from unittest import mock
import json
import os
from pathlib import Path
import tempfile
import unittest
import subprocess
import sys
import yaml

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / f'{name}.py')
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@contextlib.contextmanager
def configured_lock_fixture():
    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        config = directory / 'config.json'
        config.write_text(json.dumps({'clusters': [{'cluster': {'server': 'https://must-lock.invalid/' + directory.name}}]}))
        cli = directory / 'oc'
        cli.write_text('#!' + sys.executable + '\nimport os,sys\nfrom pathlib import Path\n'
                       'if os.environ.get("SG_TEST_OC_UNAVAILABLE") == "1": sys.exit(1)\n'
                       'print(Path(os.environ["KUBECONFIG"]).read_text())\n')
        cli.chmod(0o700)
        yield config, {**os.environ, 'PATH': str(directory) + os.pathsep + os.environ['PATH'],
                       'KUBECONFIG': str(config)}


class MustContracts(unittest.TestCase):
    def test_substrate_control_cannot_clear_project_kubeconfig(self):
        for status in (0, 7):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                scripts = root / 'scripts'
                scripts.mkdir()
                for name in ('common.sh', 'crc-control.sh'):
                    (scripts / name).write_text((ROOT / 'scripts' / name).read_text())
                config = root / '.secrets/kube/config'
                config.parent.mkdir(parents=True)
                config.write_text('project-config-must-survive')
                binaries = root / 'bin'
                binaries.mkdir()
                cli = binaries / 'crc'
                cli.write_text('#!' + sys.executable + '\nimport os,sys\nfrom pathlib import Path\n'
                               'assert sys.argv[1:] == ["stop"]\n'
                               'p=Path(os.environ["KUBECONFIG"])\n'
                               'assert p != Path(os.environ["SG_TEST_PROJECT_CONFIG"])\n'
                               'assert p.read_text() == "project-config-must-survive"\n'
                               'p.write_text("cleared-by-control")\n'
                               'sys.exit(int(os.environ["SG_TEST_CONTROL_STATUS"]))\n')
                cli.chmod(0o700)
                result = subprocess.run(['bash', str(scripts / 'crc-control.sh'), 'stop'],
                                        capture_output=True, text=True, timeout=5,
                                        env={**os.environ, 'PATH': str(binaries) + os.pathsep + os.environ['PATH'],
                                             'SG_TEST_PROJECT_CONFIG': str(config), 'SG_TEST_CONTROL_STATUS': str(status)})
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertEqual(config.read_text(), 'project-config-must-survive')
                self.assertEqual(list((root / '.cache').glob('crc-control.*')), [])

    def test_deploy_values_parse_as_yaml(self):
        for path in (ROOT / 'deploy').rglob('*.yaml'):
            self.assertIsInstance(yaml.safe_load(path.read_text()), dict, path.name)

    def test_target_lock_rejects_concurrent_writer(self):
        command = [sys.executable, str(ROOT / 'scripts/with-lock.py'), sys.executable, '-c']
        env = {**os.environ, 'KUBECONFIG': '/dev/null'}
        first = subprocess.Popen(command + ['import time; print("ready", flush=True); time.sleep(1)'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
        try:
            self.assertEqual(first.stdout.readline().strip(), 'ready')
            second = subprocess.run(command + ['print("unexpected mutation")'], capture_output=True, text=True, timeout=5, env=env)
            self.assertEqual(second.returncode, 75)
            self.assertNotIn('unexpected mutation', second.stdout)
        finally:
            first.wait(timeout=5)
            first.stdout.close()
            first.stderr.close()

    def test_lock_survives_worker_descriptor_cleanup(self):
        wrapper = str(ROOT / 'scripts/with-lock.py')
        child = 'import subprocess,sys; sys.exit(subprocess.call([sys.executable,sys.argv[1],"--check"],close_fds=True))'
        result = subprocess.run([sys.executable, wrapper, sys.executable, '-c', child, wrapper], capture_output=True, timeout=10, env={**os.environ, 'KUBECONFIG': '/dev/null'})
        self.assertEqual(result.returncode, 0, result.stderr.decode())

    def test_owned_lock_survives_cli_outage_with_unchanged_config(self):
        wrapper = str(ROOT / 'scripts/with-lock.py')
        child = ('import os,subprocess,sys; os.environ["SG_TEST_OC_UNAVAILABLE"]="1"; '
                 'sys.exit(subprocess.call([sys.executable,sys.argv[1],"--check"],close_fds=True))')
        with configured_lock_fixture() as (_, env):
            result = subprocess.run([sys.executable, wrapper, sys.executable, '-c', child, wrapper],
                                    capture_output=True, timeout=10, env=env)
        self.assertEqual(result.returncode, 0, result.stderr.decode())

    def test_inherited_target_does_not_cover_changed_config(self):
        wrapper = str(ROOT / 'scripts/with-lock.py')
        child = ('import os,json,subprocess,sys; from pathlib import Path; '
                 'p=Path(os.environ["KUBECONFIG"]); d=json.loads(p.read_text()); '
                 'd["clusters"][0]["cluster"]["server"]+="/other"; p.write_text(json.dumps(d)); '
                 'r=subprocess.run([sys.executable,sys.argv[1],"--check"],close_fds=True); '
                 'sys.exit(0 if r.returncode == 1 else 1)')
        with configured_lock_fixture() as (_, env):
            result = subprocess.run([sys.executable, wrapper, sys.executable, '-c', child, wrapper],
                                    capture_output=True, timeout=10, env=env)
        self.assertEqual(result.returncode, 0, result.stderr.decode())

    def test_unresolved_configured_target_cannot_take_bootstrap_lock(self):
        with configured_lock_fixture() as (_, env):
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/with-lock.py'),
                                     sys.executable, '-c', 'print("unexpected mutation")'],
                                    capture_output=True, text=True, timeout=10,
                                    env={**env, 'SG_TEST_OC_UNAVAILABLE': '1'})
        self.assertEqual(result.returncode, 78)
        self.assertNotIn('unexpected mutation', result.stdout)

    def test_state_computed_jwt_is_rejected(self):
        jwt = 'ey' + 'Jheader.eyJpayload.signature'
        doc = {'resources': [{'type': 'kubernetes_secret', 'name': 'reviewer', 'instances': [
            {'attributes': {'data': {'token': jwt}}}]}]}
        self.assertTrue(module('state-audit').findings(doc))
        self.assertNotIn(jwt, str(module('state-audit').findings(doc)))

    def test_public_ca_is_not_credential(self):
        doc = {'resources': [{'type': 'local_file', 'name': 'ca', 'instances': [
            {'attributes': {'content': 'public certificate'}}]}]}
        self.assertEqual(module('state-audit').findings(doc), [])

    def test_ux_exception_rejects_other_changes(self):
        rules = {'ux': ['publish']}
        check = module('allowed-changes').allowed
        self.assertTrue(check({'phase': 'ux', 'failed_total': 0, 'changed_total': 1, 'changed_tasks': ['publish']}, rules))
        for changes in (['build'], ['publish', 'delete pod'], []):
            self.assertFalse(check({'phase': 'ux', 'failed_total': 0, 'changed_total': 1, 'changed_tasks': changes}, rules))

    def test_digest_relocation_and_script_changes(self):
        digest = module('input-digest').digest
        with tempfile.TemporaryDirectory() as tmp:
            a, b = Path(tmp) / 'a', Path(tmp) / 'b'
            for root in (a, b):
                (root / 'scripts').mkdir(parents=True)
                (root / 'scripts/run.sh').write_text('same input')
            self.assertEqual(digest(a), digest(b))
            (b / 'scripts/run.sh').write_text('changed input')
            self.assertNotEqual(digest(a), digest(b))
            old = digest(a)
            (a / '.secrets').mkdir()
            (a / '.secrets/value').write_text('not an input')
            self.assertEqual(old, digest(a))
            (a / 'ui/tests/.auth').mkdir(parents=True)
            (a / 'ui/tests/.auth/session.json').write_text('private generated browser state')
            self.assertEqual(old, digest(a))

    def test_jwt_canary_matches_scan_without_printing_value(self):
        canary = b'ey' + b'Jheader.eyJpayload.signature'
        self.assertTrue(any(p.search(canary) for p in module('scan-secrets').patterns()))

    def test_scan_public_identifier_exception_is_path_and_field_specific(self):
        values = module('scan-secrets').credential_values
        data = {'app_name': 'shift-gear', 'session_secret': 'fixture-secret', 'new_field': 'private-default'}
        self.assertEqual(values('shift-gear/config/app-config', data), [b'fixture-secret', b'private-default'])
        self.assertIn(b'shift-gear', values('other/path', data))
        self.assertEqual(values('shift-gear/config/app-config', {'app_name': 'unexpected-private-value'}), [b'unexpected-private-value'])
        self.assertEqual(values('shift-gear/agent/demo-secret', {'demo_feature_flag': 'agent-sidecar-demo', 'demo_api_key': 'fixture-secret'}), [b'fixture-secret'])

    def test_release_receipt_cannot_reuse_other_revision_or_partial_ladder(self):
        valid = module('verify-proof').valid
        base = {'schemaVersion': '1', 'scope': 'live', 'result': 'pass', 'dirty': False,
                'revision': 'revision', 'inputDigest': 'digest', 'clusterId': 'cluster',
                'runId': 'run', 'finishedAt': 'now', 'steps': [{'command': ['make', 'check'], 'exitCode': 0}]}
        self.assertFalse(valid(base, 'revision', 'digest'))
        self.assertFalse(valid({**base, 'revision': 'old'}, 'revision', 'digest'))
        self.assertFalse(valid({**base, 'scope': 'offline'}, 'revision', 'digest'))

    def test_live_scan_missing_required_sources_fails_incomplete(self):
        scanner = module('scan-secrets')
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / 'safe.json'
            target.write_text('{}')
            real_spec = importlib.util.spec_from_file_location
            with mock.patch.object(scanner, 'ROOT', root), mock.patch.object(scanner, 'SECRETS', root / '.secrets'), \
                    mock.patch.object(sys, 'argv', ['scan', str(target)]), \
                    mock.patch.dict(os.environ, {'SG_SCAN_MODE': 'live'}), \
                    mock.patch.object(scanner.subprocess, 'run', side_effect=OSError('unavailable')), \
                    mock.patch.object(scanner.importlib.util, 'spec_from_file_location', wraps=importlib.util.spec_from_file_location) as spec:
                # The state checker is real; only the target tree is isolated.
                spec.side_effect = lambda name, _path: real_spec(name, ROOT / 'scripts/state-audit.py')
                with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    self.assertTrue(scanner.main())
            report = json.loads((root / '.build/gates/evidence-scan.json').read_text())
            self.assertEqual(report['result'], 'fail')
            self.assertEqual(report['source_coverage'], {'approle': 'incomplete', 'kv': 'incomplete'})

    def test_prior_or_foreign_gates_cannot_certify_current_attempt(self):
        matches = module('evidence').gate_matches
        gate = {'run_id': 'run-a', 'cluster_id': 'cluster-a'}
        self.assertTrue(matches(gate, gate, 'cluster-a', 'run-a'))
        self.assertFalse(matches(gate, gate, 'cluster-b', 'run-a'))
        self.assertFalse(matches(gate, gate, 'cluster-a', 'run-b'))
        self.assertFalse(matches(gate, {'run_id': 'run-b', 'cluster_id': 'cluster-a'}, 'cluster-a', 'run-a'))

    def test_rotation_metadata_exception_requires_exact_path_field_and_shape(self):
        values = module('scan-secrets').credential_values
        doc = {'rotated_at': '2026-10-14T10:00:00Z', 'rotation_id': '5a82bab4-d7c8-4c93-9515-4c9ffdc8234d', 'session_secret': 'private-default'}
        self.assertEqual(values('shift-gear/config/app-config', doc), [b'private-default'])
        self.assertEqual(len(values('other/path', doc)), 3)
        self.assertEqual(values('shift-gear/config/app-config', {'rotated_at': 'private-value'}), [b'private-value'])

    def test_phase_ownership_registry(self):
        rules = json.loads((ROOT / 'scripts/idempotency-tasks.json').read_text())
        self.assertEqual(set(rules), {'ux'})
        self.assertEqual(len(rules['ux']), 1)


if __name__ == '__main__':
    unittest.main()
