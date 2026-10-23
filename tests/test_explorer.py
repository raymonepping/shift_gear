"""Public declaration provenance must bind exact source bytes and exclude extra fields."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('explorer_evidence', ROOT / 'scripts/evidence.py')
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


class ExplorerPublication(unittest.TestCase):
    def test_registry_projection_and_exact_byte_provenance(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'policies').mkdir()
            for name in ('ownership-map.json', 'boundary-matrix.json'):
                value = json.loads((ROOT / 'policies' / name).read_text())
                if isinstance(value, dict):
                    value['private'] = 'secret-fixture'
                    value['rows'][0]['private'] = 'secret-fixture'
                else:
                    value[0]['private'] = 'secret-fixture'
                raw = json.dumps(value) + '\n\n'
                (root / 'policies' / name).write_text(raw)
            with patch.object(evidence, 'ROOT', root):
                result = evidence.explorer_declaration('a' * 64)
            self.assertEqual(result['inputDigest'], 'a' * 64)
            self.assertNotIn('secret-fixture', json.dumps(result))
            self.assertEqual(len(result['boundary']), 19)
            for source in result['sources'].values():
                self.assertEqual(source['sha256'], hashlib.sha256((root / source['path']).read_bytes()).hexdigest())

    def test_missing_or_invalid_registry_is_unavailable(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(evidence, 'ROOT', Path(directory)):
            self.assertIsNone(evidence.explorer_declaration('a' * 64))
            (Path(directory) / 'policies').mkdir()
            (Path(directory) / 'policies/ownership-map.json').write_text('{broken')
            self.assertIsNone(evidence.explorer_declaration('a' * 64))
