"""Unit tests for the sg_stats Ansible callback.

Tests the write_stats function directly (no Ansible runtime needed).
Run: python3 -m unittest tests/test_sg_stats.py
"""
import json
import os
import tempfile
import unittest
import datetime

# Add the callback to path
import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'ansible', 'plugins', 'callback'))

from sg_stats import write_stats, summarize  # noqa: E402


class FakeStats:
    def __init__(self, hosts):
        self.processed = hosts
        self._data = hosts

    def summarize(self, host):
        return self._data.get(host, {})


class TestWriteStats(unittest.TestCase):
    def test_changed_total(self):
        hosts = {
            "localhost": {"ok": 10, "changed": 2, "failures": 0,
                          "unreachable": 0, "skipped": 1, "rescued": 0, "ignored": 0},
        }
        with tempfile.TemporaryDirectory() as d:
            path = write_stats(d, "converge", hosts, check_mode=False,
                               now=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc))
            with open(path) as f:
                doc = json.load(f)
        self.assertEqual(doc["changed_total"], 2)
        self.assertEqual(doc["failed_total"], 0)
        self.assertEqual(doc["phase"], "converge")
        self.assertFalse(doc["check_mode"])

    def test_check_mode_suffix(self):
        hosts = {"localhost": {"ok": 5, "changed": 0, "failures": 0,
                               "unreachable": 0, "skipped": 0, "rescued": 0, "ignored": 0}}
        with tempfile.TemporaryDirectory() as d:
            path = write_stats(d, "converge", hosts, check_mode=True)
            self.assertIn(".check.json", path)
            with open(path) as f:
                doc = json.load(f)
        self.assertTrue(doc["check_mode"])
        self.assertEqual(doc["changed_total"], 0)

    def test_zero_changed_on_converged(self):
        hosts = {"localhost": {"ok": 20, "changed": 0, "failures": 0,
                               "unreachable": 0, "skipped": 3, "rescued": 0, "ignored": 0}}
        with tempfile.TemporaryDirectory() as d:
            path = write_stats(d, "identity", hosts, check_mode=False)
            with open(path) as f:
                doc = json.load(f)
        self.assertEqual(doc["changed_total"], 0)

    def test_atomic_write(self):
        """File must not exist as .tmp after write."""
        hosts = {"h1": {"ok": 1, "changed": 0, "failures": 0,
                        "unreachable": 0, "skipped": 0, "rescued": 0, "ignored": 0}}
        with tempfile.TemporaryDirectory() as d:
            write_stats(d, "baseline", hosts, check_mode=False)
            self.assertFalse(os.path.exists(os.path.join(d, "baseline.json.tmp")))
            self.assertTrue(os.path.exists(os.path.join(d, "baseline.json")))


if __name__ == "__main__":
    unittest.main()
