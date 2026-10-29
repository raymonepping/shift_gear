"""Offline tests for the two-party Secure Door (stdlib unittest; no Vault, no cluster).

The verifier and the client each read their *own* snapshot file, as their own
Vault Agents would render them; a test controls when each one "sees" a rotation.
"""
from __future__ import annotations

import ast
import io
import json
import os
import re
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from secure_door import health, protocol, snapshot  # noqa: E402
from secure_door.client import Client  # noqa: E402
from secure_door.verifier import Verifier  # noqa: E402

V1, V2, V3 = "A" * 32, "B" * 32, "C" * 32


class Clock:
    def __init__(self):
        self.t = 1_800_000_000.0

    def __call__(self):
        return self.t


def render(path, value, version):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump({"data": {"value": value}, "metadata": {"version": version,
                   "created_time": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")}}, f)
    os.replace(tmp, path)


class World:
    """Two parties, two snapshot files (two Agents), one shared probe result."""

    def __init__(self, grace: float):
        self.tmp = tempfile.TemporaryDirectory()
        d = self.tmp.name
        self.vsnap, self.csnap = os.path.join(d, "v.json"), os.path.join(d, "c.json")
        probe = os.path.join(d, "probe.json")
        with open(probe, "w") as f:
            json.dump({"reachable": True, "sealed": False, "rc": 0,
                       "at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}, f)
        common = {"DOOR_PROBE_FILE": probe, "DOOR_AGENT_LOG": os.path.join(d, "none.log")}
        self.clock = Clock()
        self.out = io.StringIO()
        self.verifier = Verifier({**common, "DOOR_SNAPSHOT_FILE": self.vsnap, "DOOR_GRACE_SECONDS": str(grace)},
                                 out=self.out, clock=self.clock)
        self.client = Client({**common, "DOOR_SNAPSHOT_FILE": self.csnap, "DOOR_STATE_FILE": os.path.join(d, "last.json")},
                             out=self.out, send=self._send)
        self.client.next_request = float("inf")      # knock explicitly

    def _send(self, body):
        body = dict(body, ts=int(self.clock()))       # the verifier's clock is authoritative in tests
        body["sig"] = protocol.sign(self._secret_for(body["key_version"]), body["client"], body["ts"], body["nonce"])
        return self.verifier.check(body)

    def _secret_for(self, version):
        for s in (self.client.cached, self.client.previous):
            if s and s.version == version:
                return s.value
        raise AssertionError("client signed with a version it does not hold")

    def both_see(self, value, version):
        render(self.vsnap, value, version)
        render(self.csnap, value, version)
        self.verifier.poll_once()
        self.client.poll_once()

    def knock(self):
        return self.client.knock()


class ProtocolTests(unittest.TestCase):
    def test_sign_and_shape(self):
        req = protocol.new_request(V1, 1, "door-client", now=100)
        self.assertIsNone(protocol.check_shape(req))
        self.assertEqual(req["sig"], protocol.sign(V1, "door-client", 100, req["nonce"]))
        self.assertNotEqual(req["sig"], protocol.sign(V2, "door-client", 100, req["nonce"]))
        self.assertEqual(len(req["nonce"]), 32)
        for bad in (None, [], {**req, "nonce": "short"}, {**req, "sig": "3f2a9c1b0d4e"}, {**req, "key_version": True}):
            self.assertEqual(protocol.check_shape(bad), "malformed")

    def test_nonce_cache(self):
        cache = protocol.NonceCache(window_s=30)
        self.assertFalse(cache.seen_before("n1", 1000))
        self.assertTrue(cache.seen_before("n1", 1010))
        self.assertFalse(cache.seen_before("n1", 1000 + 61))   # outside 2x window: forgotten


class VerifierTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.v = Verifier({"DOOR_PROBE_FILE": "/nonexistent", "DOOR_AGENT_LOG": "/nonexistent", "DOOR_GRACE_SECONDS": "30"},
                          out=io.StringIO(), clock=self.clock)
        self.v.adopt(1, V1, None)

    def req(self, secret, version, **over):
        r = protocol.new_request(secret, version, "door-client", now=self.clock())
        r.update(over)
        if "sig" not in over:
            r["sig"] = protocol.sign(secret, r["client"], r["ts"], r["nonce"])
        return r

    def test_granted_and_every_refusal_reason(self):
        self.assertEqual(self.v.check(self.req(V1, 1))["verdict"], "GRANTED")
        self.assertEqual(self.v.check(self.req(V2, 1))["reason"], "bad-signature")
        self.assertEqual(self.v.check(self.req(V1, 1, ts=int(self.clock()) - 60))["reason"], "stale-timestamp")
        self.assertEqual(self.v.check(self.req(V2, 2))["reason"], "version-unknown")
        self.assertEqual(self.v.check({"not": "a request"})["reason"], "malformed")

    def test_replayed_nonce_is_refused(self):
        r = self.req(V1, 1)
        self.assertEqual(self.v.check(r)["verdict"], "GRANTED")
        again = self.v.check(dict(r))
        self.assertEqual((again["verdict"], again["reason"]), ("DENIED", "replayed-nonce"))
        self.assertEqual(self.v.status()["verifier"]["recent"][0]["client"], "door-client")

    def test_grace_then_retired(self):
        self.v.adopt(2, V2, None)
        self.assertTrue(self.v.check(self.req(V1, 1))["reason"].startswith("grace"))
        self.clock.t += 31
        self.assertEqual(self.v.check(self.req(V1, 1))["reason"], "version-retired")
        self.assertEqual(self.v.check(self.req(V2, 2))["verdict"], "GRANTED")

    def test_strict_retires_immediately(self):
        self.v.grace_s = 0
        self.v.adopt(2, V2, None)
        self.assertEqual(self.v.check(self.req(V1, 1))["reason"], "version-retired")

    def test_status_never_carries_a_value(self):
        self.v.adopt(2, V2, None)
        raw = json.dumps(self.v.status())
        self.assertNotIn(V1, raw)
        self.assertNotIn(V2, raw)


class TwoPartyTests(unittest.TestCase):
    def test_grace_rotation_has_zero_denials_whoever_sees_it_first(self):
        for first in ("verifier", "client"):
            w = World(grace=30)
            w.both_see(V1, 1)
            self.assertEqual(w.knock()["verdict"], "GRANTED")
            target = w.vsnap if first == "verifier" else w.csnap
            render(target, V2, 2)
            (w.verifier if first == "verifier" else w.client).poll_once()
            self.assertEqual(w.knock()["verdict"], "GRANTED", f"{first} first")
            render(w.vsnap, V2, 2)
            render(w.csnap, V2, 2)
            w.verifier.poll_once()
            w.client.poll_once()
            self.assertEqual(w.knock()["verdict"], "GRANTED")
            self.assertEqual(w.client.outcomes.get("DENIED", 0), 0, f"{first} first")
        self.assertGreaterEqual(w.client.outcomes["fallback"], 1)       # client-first used the previous key

    def test_strict_rotation_has_a_measured_denial_window(self):
        w = World(grace=0)
        w.both_see(V1, 1)
        w.knock()
        render(w.vsnap, V2, 2)
        w.verifier.poll_once()                       # verifier adopts first, retires v1 at once
        for _ in range(3):
            self.assertEqual(w.knock()["reason"], "version-retired")
        render(w.csnap, V2, 2)
        w.client.poll_once()                         # client's Agent delivers v2
        self.assertEqual(w.knock()["verdict"], "GRANTED")
        window = w.client.windows[0]
        self.assertEqual((window["denied"], window["reason"], window["reasons"]), (3, "version-retired", {"version-retired": 3}))
        self.assertIsNotNone(window["seconds"])

    def test_client_later_than_grace_fails_predictably_then_recovers(self):
        w = World(grace=30)
        w.both_see(V1, 1)
        render(w.vsnap, V2, 2)
        w.verifier.poll_once()
        self.assertEqual(w.knock()["verdict"], "GRANTED")        # inside grace
        w.clock.t += 31                                          # client's Agent cut off past the grace
        self.assertEqual(w.knock()["reason"], "version-retired")
        render(w.csnap, V2, 2)
        w.client.poll_once()
        self.assertEqual(w.knock()["verdict"], "GRANTED")
        self.assertEqual(w.client.windows[0]["reason"], "version-retired")

    def test_hot_reload_keeps_the_process_and_reports_gaps(self):
        w = World(grace=30)
        w.both_see(V1, 1)
        pid = w.client.status()["pid"]
        w.both_see(V3, 4)
        self.assertEqual(w.client.cached.version, 4)
        self.assertIn("ROTATION DETECTED v1 -> v4; missed 2", w.out.getvalue())
        self.assertEqual(w.client.status()["pid"], pid)
        render(w.csnap, V2, 7)                                                # rotations while it was stopped
        restarted = Client(dict(w.client.env), out=w.out, send=w._send)      # new process, same state file
        restarted.next_request = float("inf")
        restarted.poll_once()
        gap = restarted.rotations[0]
        self.assertEqual((gap["from"], gap["to"], gap["missed"], gap["while_stopped"]), (4, 7, 2, True))
        for value in (V1, V2, V3):
            self.assertNotIn(value, w.out.getvalue())

    def test_client_status_contract_has_no_secret_field(self):
        w = World(grace=30)
        w.both_see(V1, 1)
        w.knock()
        doc = w.client.status()
        raw = json.dumps(doc)
        self.assertNotIn(V1, raw)

        def keys(o):
            if isinstance(o, dict):
                for k, v in o.items():
                    yield k
                    yield from keys(v)
            elif isinstance(o, list):
                for x in o:
                    yield from keys(x)
        self.assertFalse({"value", "secret_value", "credential", "token", "password", "api_key"} & set(keys(doc)))


class SnapshotAndHealthTests(unittest.TestCase):
    def test_iso_keeps_milliseconds(self):
        moment = datetime(2026, 10, 29, 8, 1, 2, 345678, tzinfo=timezone.utc)
        self.assertEqual(health.iso(moment), "2026-10-29T08:01:02.345Z")
        self.assertEqual(health.parse_time(health.iso(moment)), moment.replace(microsecond=345000))

    def test_snapshot_rejects_partial_and_hides_value(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "s.json")
            with self.assertRaises(snapshot.SnapshotMissing):
                snapshot.read(p)
            with open(p, "w") as f:
                f.write('{"data": {"value": "x"')
            with self.assertRaises(snapshot.SnapshotInvalid):
                snapshot.read(p)
            render(p, V1, 3)
            s = snapshot.read(p)
            self.assertNotIn(V1, repr(s) + str(s))

    def test_agent_log_evidence(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "agent.log")
            with open(p, "w") as f:
                f.write("2026-10-28T12:00:00.000Z [TRACE] (view) vault.read(kv/data/x): marking successful data response\n")
                f.write("2026-10-28T12:00:05.000Z [ERROR] (view) vault.read(kv/data/x): permission denied\n")
            ev = health.scan_agent_log(p, health.AgentEvidence())
            self.assertTrue(ev.observable)
            self.assertNotIn("permission", ev.last_error)


class StaticTests(unittest.TestCase):
    def test_stdlib_only_and_no_vault_access(self):
        pkg = HERE.parent / "secure_door"
        for py in pkg.glob("*.py"):
            text = py.read_text()
            self.assertIsNone(re.search(r"[\"']VAULT_", text), f"{py.name}: no VAULT_* settings")
            self.assertNotIn(":8200", text, f"{py.name}: the parties never talk to Vault")
            for node in ast.walk(ast.parse(text)):
                names = [a.name for a in node.names] if isinstance(node, ast.Import) else \
                    [node.module] if isinstance(node, ast.ImportFrom) and node.level == 0 and node.module else []
                for n in names:
                    self.assertIn(n.split(".")[0], sys.stdlib_module_names, f"{py.name} imports {n}")


if __name__ == "__main__":
    unittest.main()
