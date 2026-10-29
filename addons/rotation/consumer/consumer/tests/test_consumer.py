"""Offline tests for the Secure Door consumer (stdlib unittest; no Vault, no cluster)."""
from __future__ import annotations

import ast
import re
import io
import json
import os
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from secure_door import door, health, snapshot  # noqa: E402
from secure_door.app import Consumer  # noqa: E402

VALUE = "Q" * 32


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S.%fZ")


class Files:
    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory()  # cleaned up when the Files object is collected
        d = self.tmp.name
        self.snap = os.path.join(d, "secret.json")
        self.probe = os.path.join(d, "vault.json")
        self.agent_log = os.path.join(d, "agent.log")
        self.status = os.path.join(d, "state.json")
        self.state = os.path.join(d, "last-version.json")

    def render(self, value, version, created=None):
        doc = {"data": {"value": value},
               "metadata": {"version": version, "created_time": created or iso(datetime.now(timezone.utc))}}
        tmp = self.snap + ".tmp"
        with open(tmp, "w") as f:
            json.dump(doc, f)
        os.replace(tmp, self.snap)

    def probe_result(self, reachable=True, sealed=False, at=None):
        with open(self.probe, "w") as f:
            json.dump({"reachable": reachable, "sealed": sealed, "rc": 0 if reachable else 1,
                       "at": iso(at or datetime.now(timezone.utc))}, f)

    def env(self):
        return {"CONSUMER_SNAPSHOT_FILE": self.snap, "CONSUMER_PROBE_FILE": self.probe,
                "CONSUMER_AGENT_LOG": self.agent_log, "CONSUMER_STATUS_FILE": self.status,
                "CONSUMER_STATE_FILE": self.state, "CONSUMER_VALIDATE_S": "3600", "CONSUMER_STALE_AFTER_S": "60"}


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.f = Files()

    def test_missing_partial_malformed(self):
        with self.assertRaises(snapshot.SnapshotMissing):
            snapshot.read(self.f.snap)
        for bad in ["", '{"data": {"value": "x"', "[]", '{"data": {}, "metadata": {"version": 1}}',
                    '{"data": {"value": "x"}, "metadata": {"version": 0}}',
                    '{"data": {"value": "x"}, "metadata": {"version": true}}']:
            with open(self.f.snap, "w") as fh:
                fh.write(bad)
            with self.assertRaises(snapshot.SnapshotInvalid, msg=bad):
                snapshot.read(self.f.snap)

    def test_value_never_in_repr_or_str(self):
        self.f.render(VALUE, 3)
        snap = snapshot.read(self.f.snap)
        self.assertEqual(snap.version, 3)
        self.assertNotIn(VALUE, repr(snap))
        self.assertNotIn(VALUE, str(snap))
        self.assertEqual(len(snap.fingerprint), 12)


class DoorTests(unittest.TestCase):
    def setUp(self):
        self.f = Files()
        self.door = door.SecureDoor(self.f.snap)

    def test_granted_denied_unavailable(self):
        self.assertEqual(self.door.check(VALUE).verdict, "UNAVAILABLE")
        self.f.render(VALUE, 5)
        v = self.door.check(VALUE)
        self.assertEqual((v.verdict, v.checked_version), ("GRANTED", 5))
        self.assertIn("no issuer exists", v.meaning)
        self.assertEqual(self.door.check("R" * 32).verdict, "DENIED")

    def test_fingerprint_is_never_a_credential(self):
        self.f.render(VALUE, 5)
        fp = snapshot.read(self.f.snap).fingerprint
        self.assertEqual(self.door.check(fp).verdict, "DENIED")

    def test_door_reads_the_snapshot_independently(self):
        self.f.render(VALUE, 5)
        self.f.render("S" * 32, 6)          # rotated after the caller cached VALUE
        v = self.door.check(VALUE)
        self.assertEqual((v.verdict, v.checked_version), ("DENIED", 6))


class HealthTests(unittest.TestCase):
    def setUp(self):
        self.f = Files()

    def test_probe_states(self):
        prev = health.VaultProbe()
        self.assertEqual(health.read_probe(self.f.probe, prev, 15).state, "unknown")
        self.f.probe_result(True)
        p = health.read_probe(self.f.probe, prev, 15)
        self.assertEqual(p.state, "reachable")
        self.f.probe_result(False)
        p2 = health.read_probe(self.f.probe, p, 15)
        self.assertEqual(p2.state, "unreachable")
        self.f.probe_result(True, sealed=True)
        self.assertEqual(health.read_probe(self.f.probe, p2, 15).state, "sealed")
        self.f.probe_result(True, at=datetime.now(timezone.utc) - timedelta(minutes=5))
        self.assertEqual(health.read_probe(self.f.probe, p2, 15).state, "unknown")

    def test_agent_log_evidence(self):
        ev = health.AgentEvidence()
        with open(self.f.agent_log, "w") as fh:
            fh.write("2026-10-28T12:00:00.000Z [TRACE] (view) vault.read(kv/data/x): marking successful data response\n")
            fh.write("2026-10-28T12:00:05.000Z [ERROR] (view) vault.read(kv/data/x): permission denied\n")
            fh.write("partial line without newline")
        ev = health.scan_agent_log(self.f.agent_log, ev)
        self.assertTrue(ev.observable)
        self.assertEqual(ev.last_refresh.second, 0)
        self.assertIsNotNone(ev.last_error_at)
        self.assertNotIn("permission", ev.last_error)


class ConsumerTests(unittest.TestCase):
    def setUp(self):
        self.f = Files()
        self.out = io.StringIO()
        self.f.probe_result(True)

    def consumer(self):
        return Consumer(self.f.env(), out=self.out)

    def test_hot_reload_without_restart_and_door_sequence(self):
        c = self.consumer()
        self.f.render(VALUE, 54)
        c.poll_once()
        self.assertEqual(c.cached.version, 54)
        self.f.render("T" * 32, 55)
        c.poll_once()
        self.f.render("U" * 32, 56)
        c.poll_once()
        self.assertEqual(c.cached.version, 56)
        log = self.out.getvalue()
        self.assertIn("ROTATION DETECTED v54 -> v55", log)
        self.assertIn("STALE CREDENTIAL REJECTED version=v54", log)
        self.assertIn("ACCESS GRANTED version=v55", log)
        self.assertIn("ROTATION DETECTED v55 -> v56", log)
        rot = c.rotations[0]
        self.assertTrue(rot["stale_denied"] and rot["fresh_granted"])
        for v in (VALUE, "T" * 32, "U" * 32):
            self.assertNotIn(v, log)

    def test_gap_while_running_and_after_restart(self):
        c = self.consumer()
        self.f.render(VALUE, 54)
        c.poll_once()
        self.f.render("V" * 32, 58)
        c.poll_once()
        self.assertIn("ROTATION DETECTED v54 -> v58; missed 3 intermediate version(s)", self.out.getvalue())
        # a restart (new process) after more rotations
        self.f.render("W" * 32, 61)
        c2 = self.consumer()
        c2.poll_once()
        self.assertIn("v58 -> v61 while stopped; missed 2", self.out.getvalue())
        self.assertEqual(c2.rotations[0]["missed"], 2)

    def test_race_retries_instead_of_false_failure(self):
        c = self.consumer()
        self.f.render(VALUE, 10)
        c.poll_once()
        real_check = c.door.check
        calls = {"n": 0}

        def racing(presented):
            calls["n"] += 1
            if calls["n"] == 2:               # the fresh check: another rotation lands first
                self.f.render("Y" * 32, 12)
            return real_check(presented)
        c.door.check = racing
        self.f.render("X" * 32, 11)
        c.poll_once()
        self.assertEqual(c.cached.version, 12)
        self.assertTrue(c.rotations[0]["fresh_granted"])

    def test_states_from_evidence_not_file_age(self):
        c = self.consumer()
        self.assertEqual(c.credential_state()[0], "no-data")
        self.f.render(VALUE, 1)
        c.poll_once()
        self.assertEqual(c.credential_state()[0], "current")
        # an unchanged, old file is never a staleness reason
        os.utime(self.f.snap, (0, 0))
        c.poll_once()
        self.assertEqual(c.credential_state()[0], "current")
        self.f.probe_result(False)
        c.poll_once()
        self.assertEqual(c.credential_state()[0], "last-known-good")
        c.probe.since = datetime.now(timezone.utc) - timedelta(seconds=120)
        self.assertEqual(c.credential_state()[0], "stale")
        os.remove(self.f.probe)
        c.probe = health.VaultProbe()
        c.poll_once()
        state, reason = c.credential_state()
        self.assertEqual((state, reason), ("last-known-good", "Vault connectivity unknown"))

    def test_malformed_snapshot_keeps_last_known_good(self):
        c = self.consumer()
        self.f.render(VALUE, 7)
        c.poll_once()
        with open(self.f.snap, "w") as fh:
            fh.write('{"data": ')
        c.poll_once()
        self.assertEqual(c.cached.version, 7)
        self.assertIn("rendered snapshot rejected", self.out.getvalue())

    def test_status_contract_has_no_secret_field(self):
        c = self.consumer()
        self.f.render(VALUE, 3)
        c.poll_once()
        c.write_status()
        with open(self.f.status) as fh:
            raw = fh.read()
        self.assertNotIn(VALUE, raw)
        doc = json.loads(raw)
        self.assertEqual(doc["schema"], 1)
        self.assertFalse(doc["agent"]["last_refresh"]["observable"])

        def keys(o):
            if isinstance(o, dict):
                for k, v in o.items():
                    yield k
                    yield from keys(v)
            elif isinstance(o, list):
                for x in o:
                    yield from keys(x)
        forbidden = {"value", "secret_value", "credential", "token", "password", "api_key"}
        self.assertFalse(forbidden & set(keys(doc)), set(keys(doc)) & forbidden)


class StdlibOnlyTests(unittest.TestCase):
    def test_no_third_party_and_no_vault_client(self):
        pkg = HERE.parent / "secure_door"
        for py in pkg.glob("*.py"):
            text = py.read_text()
            self.assertNotIn("urllib.request", text, f"{py.name}: the consumer must not make HTTP calls")
            self.assertIsNone(re.search(r"[\"']VAULT_", text), f"{py.name}: no VAULT_* settings")
            for node in ast.walk(ast.parse(text)):
                names = [a.name for a in node.names] if isinstance(node, ast.Import) else \
                    [node.module] if isinstance(node, ast.ImportFrom) and node.level == 0 and node.module else []
                for n in names:
                    self.assertIn(n.split(".")[0], sys.stdlib_module_names, f"{py.name} imports {n}")


if __name__ == "__main__":
    unittest.main()
