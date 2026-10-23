"""Behavioral guards on immutable build inputs; no cluster needed."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('pin', ROOT / 'scripts/pin-built-image.py')
pin = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pin)


class ShouldContracts(unittest.TestCase):
    def test_image_catalog_accepts_only_named_immutable_artifacts(self):
        ui = 'image-registry.openshift-image-registry.svc:5000/sg-app/shift-gear-ui@sha256:' + 'a' * 64
        ldap = 'image-registry.openshift-image-registry.svc:5000/sg-identity/openldap@sha256:' + 'b' * 64
        self.assertTrue(pin.valid_catalog({'ui_image': ui, 'openldap_image': ldap}))
        for invalid in [{'ui_image': ldap}, {'openldap_image': ui}, {'ui_image': ui.replace('@sha256:' + 'a' * 64, ':latest')},
                        {'vault_token': ui}, {'ui_image': ui.replace('image-registry.openshift-image-registry.svc:5000', 'untrusted.example')}, [], {'ui_image': 123}]:
            self.assertFalse(pin.valid_catalog(invalid))

    def test_component_summary_drops_unknown_fields_and_invalid_provenance(self):
        import datetime as dt
        spec = importlib.util.spec_from_file_location('evidence', ROOT / 'scripts/evidence.py')
        evidence = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(evidence)
        value = {'result': 'pass', 'at': dt.datetime.now(dt.timezone.utc).isoformat(), 'inputDigest': 'a' * 64,
                 'checks': {'never-export-this-key': True}, 'private_key': 'fixture-secret', 'plaintext': 'fixture-plain'}
        summary = evidence.component_proof_summary(value)
        self.assertEqual(summary['passedChecks'], 1)
        self.assertNotIn('private_key', summary)
        self.assertNotIn('plaintext', summary)
        self.assertNotIn('never-export-this-key', str(summary))
        self.assertIsNone(evidence.component_proof_summary({**value, 'at': (dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=1)).isoformat()}))
        self.assertIsNone(evidence.component_proof_summary({**value, 'inputDigest': 'arbitrary secret'}))

    def test_release_requires_each_ordered_scenario_and_postcondition(self):
        import copy
        def module(name):
            spec = importlib.util.spec_from_file_location(name, ROOT / f'scripts/{name}.py')
            result = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(result)
            return result
        ladder, verifier = module('proof_steps'), module('verify-proof')
        receipt = {'schemaVersion': '1', 'scope': 'live', 'result': 'pass', 'dirty': False,
                   'revision': 'revision', 'inputDigest': 'digest', 'clusterId': 'cluster', 'runId': 'run', 'finishedAt': 'now',
                   'steps': [{'index': i, 'command': command, 'exitCode': 0} for i, command in enumerate(ladder.commands(ROOT, True))]}
        self.assertTrue(verifier.valid(receipt, 'revision', 'digest'))
        for change in ['duplicate', 'missing-verify', 'reordered', 'failed']:
            changed = copy.deepcopy(receipt)
            steps = changed['steps']
            scenario_indices = [i for i, step in enumerate(steps) if step['command'][0] == 'bash']
            if change == 'duplicate':
                steps[scenario_indices[1]]['command'] = steps[scenario_indices[0]]['command']
            elif change == 'missing-verify':
                steps.pop(scenario_indices[0] + 1)
            elif change == 'reordered':
                steps[3]['command'], steps[4]['command'] = steps[4]['command'], steps[3]['command']
            else:
                steps[-1]['exitCode'] = 1
            self.assertFalse(verifier.valid(changed, 'revision', 'digest'), change)
