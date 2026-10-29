"""Offline tests for the KV rotation controller (stdlib unittest; no network)."""
from __future__ import annotations

import ast
import io
import json
import logging
import os
import sys
import tempfile
import unittest
from datetime import timedelta
from pathlib import Path
from unittest import mock

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))

from fakes import FakeClock, FakeVault  # noqa: E402
from rotation import compliance, controller as ctl, history as h, triggers  # noqa: E402
from rotation.config import ConfigError, parse, parse_duration  # noqa: E402
from rotation.events import EventTail, normalise, parse_line  # noqa: E402
from rotation.generators import generate, policy_violations  # noqa: E402
from rotation.redact import REGISTRY, configure_logging, fingerprint  # noqa: E402
from rotation.usage import UsageCounter  # noqa: E402
from rotation.vault import iso_precise, parse_time  # noqa: E402

ROTATION_YAML = HERE.parents[1] / "rotation.yaml"


def doc(**overrides) -> dict:
    base = {
        "rotation": {
            "mount": "kv", "prefix": "shift-gear/rotation", "loop_seconds": 10,
            "defaults": {"max_versions": 5},
            "types": {
                "api-key": {"generator": {"kind": "chars", "charset": "alnum", "length": 32},
                            "schedule": {"interval": "60s"},
                            "policy": {"max_age": "5m", "min_length": 32, "max_reads": 5}},
                "signing-key": {"generator": {"kind": "bytes", "bytes": 48, "encoding": "base64url"},
                                "schedule": {"interval": "5m"}, "policy": {"max_age": "15m", "min_length": 64}},
                "service-password": {"generator": {"kind": "password", "length": 24,
                                                   "classes": ["lower", "upper", "digit", "symbol"]},
                                     "schedule": {"interval": "10m"}, "policy": {"max_age": "30m", "min_length": 20}},
            },
            "secrets": [
                {"name": "demo", "type": "api-key", "strategies": ["time", "usage", "event"], "usage": {"max_reads": 3}},
                {"name": "session-signing", "type": "signing-key", "strategies": ["time", "event"],
                 "events": [{"match": "kv-v2/data-*", "path": "shift-gear/config/app-config"}]},
            ],
        }
    }
    base["rotation"].update(overrides)
    return base


class ConfigTests(unittest.TestCase):
    def test_shipped_config_is_valid(self):
        try:
            import yaml  # Ansible's interpreter has it; the runtime does not need it
        except ImportError:
            self.skipTest("PyYAML not available in this interpreter")
        cfg = parse(yaml.safe_load(ROTATION_YAML.read_text()))
        self.assertGreaterEqual(len(cfg.secrets), 3)
        self.assertEqual(cfg.secret("api-key/demo").rel_path, "shift-gear/rotation/api-key/demo")

    def test_durations(self):
        self.assertEqual(parse_duration("60s", "x"), 60)
        self.assertEqual(parse_duration("5m", "x"), 300)
        self.assertEqual(parse_duration("30d", "x"), 30 * 86400)
        for bad in ("5", "0s", "1w", "-1m", ""):
            with self.assertRaises(ConfigError):
                parse_duration(bad, "x")

    def test_interval_above_max_age_rejected(self):
        d = doc()
        d["rotation"]["types"]["api-key"]["schedule"]["interval"] = "10m"
        with self.assertRaisesRegex(ConfigError, "exceeds policy.max_age"):
            parse(d)

    def test_override_cannot_loosen(self):
        d = doc()
        d["rotation"]["secrets"][0]["interval"] = "6m"
        with self.assertRaisesRegex(ConfigError, "loosens"):
            parse(d)
        d = doc()
        d["rotation"]["secrets"][0]["usage"]["max_reads"] = 9
        with self.assertRaisesRegex(ConfigError, "loosens"):
            parse(d)

    def test_generator_must_meet_min_length(self):
        d = doc()
        d["rotation"]["types"]["api-key"]["policy"]["min_length"] = 40
        with self.assertRaisesRegex(ConfigError, "below policy.min_length"):
            parse(d)

    def test_entropy_floor(self):
        d = doc()
        d["rotation"]["types"]["api-key"]["generator"]["length"] = 8
        d["rotation"]["types"]["api-key"]["policy"]["min_length"] = 8
        with self.assertRaisesRegex(ConfigError, "entropy floor"):
            parse(d)

    def test_self_trigger_rejected(self):
        d = doc()
        d["rotation"]["secrets"][1]["events"][0]["path"] = "shift-gear/rotation/api-key/demo"
        with self.assertRaisesRegex(ConfigError, "rotation loop"):
            parse(d)

    def test_usage_needs_max_reads(self):
        d = doc()
        d["rotation"]["types"]["signing-key"]["policy"].pop("max_reads", None)
        d["rotation"]["secrets"][1]["strategies"] = ["time", "usage"]
        d["rotation"]["secrets"][1].pop("events")
        with self.assertRaisesRegex(ConfigError, "needs usage.max_reads"):
            parse(d)

    def test_time_strategy_is_mandatory(self):
        d = doc()
        d["rotation"]["secrets"][0]["strategies"] = ["usage", "event"]
        with self.assertRaisesRegex(ConfigError, "must include 'time'"):
            parse(d)

    def test_event_rule_limits(self):
        from rotation.config import MAX_EVENT_RULES
        d = doc()
        d["rotation"]["secrets"][1]["events"] = [{"match": "kv-v2/*", "path": f"shift-gear/w/{i}"}
                                                 for i in range(MAX_EVENT_RULES + 1)]
        with self.assertRaisesRegex(ConfigError, "at most"):
            parse(d)
        d = doc()
        d["rotation"]["secrets"][1]["events"] = [{"match": "kv-v2/*", "path": "shift-gear/" + "x" * 200 + str(i)}
                                                 for i in range(3)]
        with self.assertRaisesRegex(ConfigError, "checkpoint would be"):
            parse(d)

    def test_custom_metadata_key_budget(self):
        from rotation.config import MAX_VERSIONS_LIMIT, SUMMARY_KEYS
        summary = [h.MANAGED_BY, h.TYPE, h.STRATEGIES, h.LAST_ROTATED, h.LAST_TRIGGER,
                   h.READS_SINCE, h.READS_CURSOR, h.REQUEST, h.SERVED, h.WATCH]
        self.assertEqual(len(summary), SUMMARY_KEYS)
        self.assertLessEqual(MAX_VERSIONS_LIMIT + SUMMARY_KEYS, 64)
        record = h.Record(10**6, "f" * 12, "recovered", "2026-10-28T11:16:00Z", "x" * 500).encode()
        self.assertLessEqual(len(record.encode()), 512)
        self.assertLessEqual(len(h.encode_request("u" * 100, "a" * 500, "r" * 500).encode()), 512)

    def test_duplicate_and_names(self):
        d = doc()
        d["rotation"]["secrets"].append(dict(d["rotation"]["secrets"][0]))
        with self.assertRaisesRegex(ConfigError, "duplicate"):
            parse(d)
        d = doc()
        d["rotation"]["secrets"][0]["name"] = "Bad_Name"
        with self.assertRaisesRegex(ConfigError, "DNS label"):
            parse(d)


class GeneratorTests(unittest.TestCase):
    def test_every_generation_meets_policy(self):
        cfg = parse(doc())
        for stype in cfg.types.values():
            seen = set()
            for _ in range(1000):
                value = generate(stype.generator)
                self.assertEqual(policy_violations(value, stype), [], stype.name)
                seen.add(value)
            self.assertEqual(len(seen), 1000, f"{stype.name}: values must not repeat")

    def test_policy_violation_never_echoes_value(self):
        stype = parse(doc()).types["api-key"]
        reasons = policy_violations("short$", stype)
        self.assertTrue(reasons)
        self.assertNotIn("short$", " ".join(reasons))


class HistoryTests(unittest.TestCase):
    def test_roundtrip_and_sanitising(self):
        rec = h.Record(3, "abcdef012345", "request", "2026-10-28T10:00:00Z", "cleo|evil\nline")
        decoded = h.decode({"v3": rec.encode(), "rotation_type": "api-key", "vx": "junk"})
        self.assertEqual(decoded[3].actor, "cleoevilline")
        self.assertEqual(list(decoded), [3])

    def test_prune(self):
        custom = {h.key(n): h.Record(n, "f", "time", "t", "a").encode() for n in range(1, 8)}
        removed = h.prune_keys(custom, current_version=7, max_versions=5)
        self.assertEqual(set(removed), {"v1", "v2"})
        self.assertTrue(all(v is None for v in removed.values()))

    def test_request_and_watch_encoding(self):
        self.assertEqual(h.parse_request(h.encode_request("u-1", "cleo", "rotate|now")), ("u-1", "cleo", "rotatenow"))
        self.assertIsNone(h.parse_request(""))
        self.assertEqual(h.parse_watch(h.encode_watch({"a/b": 3, "c": 10})), {"a/b": 3, "c": 10})


class TriggerTests(unittest.TestCase):
    def setUp(self):
        self.cfg = parse(doc())
        self.demo = self.cfg.secret("api-key/demo")
        self.clock = FakeClock()

    def state(self, age=0, reads=0, request=None, changed=()):
        return triggers.State(self.clock.now - timedelta(seconds=age), reads, request, tuple(changed))

    def test_nothing_due(self):
        self.assertIsNone(triggers.decide(self.demo, self.state(age=10, reads=1), self.clock.now))

    def test_each_strategy(self):
        self.assertEqual(triggers.decide(self.demo, self.state(age=61), self.clock.now).kind, "time")
        self.assertEqual(triggers.decide(self.demo, self.state(reads=3), self.clock.now).kind, "usage")
        req = triggers.decide(self.demo, self.state(request=("u1", "cleo", "why")), self.clock.now)
        self.assertEqual((req.kind, req.actor, req.request_id), ("request", "cleo", "u1"))
        signing = self.cfg.secret("signing-key/session-signing")
        self.assertEqual(triggers.decide(signing, self.state(changed=["shift-gear/config/app-config"]),
                                         self.clock.now).kind, "event")

    def test_priority_one_rotation(self):
        due = triggers.due(self.demo, self.state(age=999, reads=10, request=("u", "a", "r")), self.clock.now)
        self.assertEqual([t.kind for t in due], ["request", "usage", "time"])

    def test_strategy_not_enabled_is_ignored(self):
        batch = parse(doc(secrets=[{"name": "b", "type": "api-key", "strategies": ["time"]}])).secrets[0]
        self.assertIsNone(triggers.decide(batch, self.state(age=10, reads=99, request=("u", "a", "r")), self.clock.now))

    def test_usage_not_reported_never_triggers(self):
        self.assertIsNone(triggers.decide(self.demo, triggers.State(self.clock.now, None), self.clock.now))


class UsageTests(unittest.TestCase):
    def payload(self, entries, dropped=0, instance="i1"):
        return {"collector": {"dropped": dropped, "instanceId": instance}, "entries": entries}

    def entry(self, i, path="kv/data/shift-gear/rotation/api-key/demo", typ="request", op="read",
              dn="token-ansible-platform", t="2026-10-28T10:00:01.123456789Z", err=None, ns="shift-gear/"):
        return {"id": f"id-{i}", "type": typ, "operation": op, "path": path, "displayName": dn,
                "time": t, "error": err, "namespace": ns}

    def test_counts_requests_once_and_excludes_self(self):
        counter = UsageCounter("http://x", "kv", "shift-gear")
        counter.exclude_display_names.add("me")
        managed = {"shift-gear/rotation/api-key/demo"}
        entries = [self.entry(1), self.entry(1, typ="response"), self.entry(2), self.entry(3, dn="me"),
                   self.entry(4, op="update"), self.entry(5, err="permission denied"),
                   self.entry(6, path="kv/data/shift-gear/config/app-config"), self.entry(7, ns="other/")]
        first = counter.count(self.payload(entries), managed)
        self.assertEqual(len(first.reads["shift-gear/rotation/api-key/demo"]), 2)
        again = counter.count(self.payload(entries), managed)
        self.assertEqual(again.reads, {})          # de-duplicated on id
        self.assertFalse(again.undercount)

    def test_undercount_flag(self):
        counter = UsageCounter("http://x", "kv", "shift-gear")
        counter.count(self.payload([], dropped=0), set())
        self.assertTrue(counter.count(self.payload([], dropped=5), set()).undercount)
        self.assertTrue(counter.count(self.payload([], dropped=5, instance="i2"), set()).undercount)

    def test_unreachable_is_honest(self):
        counter = UsageCounter("http://127.0.0.1:9", "kv", "shift-gear", timeout=0.2)
        poll = counter.poll({"x"})
        self.assertFalse(poll.available)
        self.assertIn("unreachable", poll.reason)


class EventTests(unittest.TestCase):
    def test_normalise(self):
        self.assertEqual(normalise("kv/data/shift-gear/config/app-config", "kv"), "shift-gear/config/app-config")
        self.assertEqual(normalise("shift-gear/kv/metadata/a/b", "kv"), "a/b")
        self.assertIsNone(normalise("secret/data/a", "kv"))

    def test_parse_line(self):
        line = json.dumps({"data": {"event_type": "kv-v2/data-write",
                                    "event": {"metadata": {"path": "kv/data/shift-gear/config/app-config"}}}})
        ev = parse_line(line, "kv")
        self.assertEqual((ev.event_type, ev.rel_path), ("kv-v2/data-write", "shift-gear/config/app-config"))
        self.assertIsNone(parse_line("not json", "kv"))
        self.assertIsNone(parse_line(json.dumps({"data": {}}), "kv"))

    def test_tail_handles_partial_lines_and_truncation(self):
        line = json.dumps({"data": {"event_type": "kv-v2/data-write",
                                    "event": {"metadata": {"path": "kv/data/a/b"}}}})
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "stream.ndjson")
            tail = EventTail(path, "kv")
            self.assertEqual(tail.read(), [])
            with open(path, "w") as f:
                f.write(line + "\n" + line[:10])
            self.assertEqual(len(tail.read()), 1)
            with open(path, "a") as f:
                f.write(line[10:] + "\ngarbage\n")
            self.assertEqual(len(tail.read()), 1)
            with open(path, "w") as f:      # truncated / rotated
                f.write(line + "\n")
            self.assertEqual(len(tail.read()), 1)


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock()
        self.vault = FakeVault(self.clock)
        self.cfg = parse(doc())
        self.log_stream = io.StringIO()
        self.logger = configure_logging(self.log_stream, logging.DEBUG)
        self.ctl = ctl.Controller(self.cfg, self.vault, None, None, self.logger)
        patcher = mock.patch.object(ctl, "utcnow", lambda: self.clock.now)
        patcher.start()
        self.addCleanup(patcher.stop)
        # the watched core path exists at v1
        self.vault.write_metadata("shift-gear/config/app-config", 10, False, {})
        self.vault.write_value("shift-gear/config/app-config", "core", cas=0)

    def md(self, rel="shift-gear/rotation/api-key/demo"):
        return self.vault.read_metadata(rel)

    def test_onboard_then_time_rotation(self):
        self.ctl.loop_once()
        md = self.md()
        self.assertEqual(md.current_version, 1)
        self.assertTrue(md.cas_required)
        self.assertEqual(md.max_versions, 5)
        self.assertEqual(h.decode(md.custom)[1].trigger, "created")
        self.ctl.loop_once()
        self.assertEqual(self.md().current_version, 1, "not due yet")
        self.clock.advance(61)
        self.ctl.loop_once()
        md = self.md()
        self.assertEqual(md.current_version, 2)
        recs = h.decode(md.custom)
        self.assertEqual(recs[2].trigger, "time")
        self.assertNotEqual(recs[1].fingerprint, recs[2].fingerprint)

    def test_request_served_once(self):
        self.ctl.loop_once()
        self.vault.patch_metadata("shift-gear/rotation/api-key/demo",
                                  {h.REQUEST: h.encode_request("req-1", "cleo", "demo")})
        self.ctl.loop_once()
        self.ctl.loop_once()
        md = self.md()
        self.assertEqual(md.current_version, 2)
        self.assertEqual(h.decode(md.custom)[2].actor, "cleo")
        self.assertEqual(md.custom[h.SERVED], "req-1")

    def test_request_endpoint_records_in_vault(self):
        self.ctl.loop_once()
        result = self.ctl.request("api-key/demo", "cli:raymon via kubernetes exec", "demo")
        self.assertEqual(result["version"], 1)
        self.ctl.loop_once()
        rec = h.decode(self.md().custom)[2]
        self.assertEqual((rec.trigger, rec.actor), ("request", "cli:raymon via kubernetes exec"))
        with self.assertRaisesRegex(ValueError, "strategy 'event' is not enabled"):
            ctl.Controller(parse(doc(secrets=[{"name": "b", "type": "api-key", "strategies": ["time"]}])),
                           self.vault, None, None, self.logger).request("api-key/b", "x", "y")

    def test_cascade_event_via_watched_version(self):
        self.ctl.loop_once()
        signing = "shift-gear/rotation/signing-key/session-signing"
        self.assertEqual(self.md(signing).current_version, 1)
        self.vault.write_value("shift-gear/config/app-config", "core2", cas=1)
        self.ctl.loop_once()
        md = self.md(signing)
        self.assertEqual(md.current_version, 2)
        self.assertEqual(h.decode(md.custom)[2].trigger, "event")
        self.ctl.loop_once()
        self.assertEqual(self.md(signing).current_version, 2, "same watched version: no second rotation")

    def test_cascade_detects_recreated_and_deleted_watched_path(self):
        self.ctl.loop_once()
        signing = "shift-gear/rotation/signing-key/session-signing"
        self.vault.write_value("shift-gear/config/app-config", "core2", cas=1)     # v2
        self.ctl.loop_once()
        self.assertEqual(self.md(signing).current_version, 2)
        # deleted and recreated: version restarts at 1 (lower than the checkpoint)
        del self.vault.entries["shift-gear/config/app-config"]
        self.vault.write_metadata("shift-gear/config/app-config", 10, False, {})
        self.vault.write_value("shift-gear/config/app-config", "recreated", cas=0)
        self.ctl.loop_once()
        self.assertEqual(self.md(signing).current_version, 3, "recreated watched path must trigger")
        # deleted for good: also a change
        del self.vault.entries["shift-gear/config/app-config"]
        self.ctl.loop_once()
        self.assertEqual(self.md(signing).current_version, 4, "deleted watched path must trigger")
        self.ctl.loop_once()
        self.assertEqual(self.md(signing).current_version, 4, "re-baselined: no repeat")

    def test_offline_change_detected_on_start(self):
        self.ctl.loop_once()
        signing = "shift-gear/rotation/signing-key/session-signing"
        self.vault.write_value("shift-gear/config/app-config", "while-down", cas=1)
        fresh = ctl.Controller(self.cfg, self.vault, None, None, self.logger)   # a restarted controller
        fresh.loop_once()
        self.assertEqual(h.decode(self.md(signing).custom)[2].trigger, "event")

    def test_checkpoint_not_advanced_by_a_cas_skip(self):
        self.ctl.loop_once()
        signing = "shift-gear/rotation/signing-key/session-signing"
        self.vault.write_value("shift-gear/config/app-config", "core2", cas=1)
        real_write = self.vault.write_value
        def conflicting(rel, value, cas):
            if rel == signing:
                from rotation.vault import CasConflict
                raise CasConflict(400, rel, ["check-and-set parameter did not match the current version"])
            return real_write(rel, value, cas)
        self.vault.write_value = conflicting
        self.ctl.loop_once()
        self.assertIn("app-config@1", self.md(signing).custom[h.WATCH], "checkpoint must not advance on a skip")
        self.vault.write_value = real_write
        self.ctl.loop_once()
        self.assertEqual(h.decode(self.md(signing).custom)[2].trigger, "event")

    def test_identity_first_no_secret_touched_without_it(self):
        from rotation.vault import Unreachable
        calls = []
        class Refusing(FakeVault):
            def lookup_self(self):
                raise Unreachable("agent not ready")
            def read_metadata(self, rel):
                calls.append(rel)
                return super().read_metadata(rel)
        vault = Refusing(self.clock)
        c = ctl.Controller(self.cfg, vault, None, None, self.logger)
        c.loop_once()
        self.assertEqual(calls, [])
        self.assertEqual(vault.writes, [])
        self.assertIn("vault not ready", c.last_error)

    def test_usage_rotation_and_reset(self):
        self.ctl.loop_once()
        self.ctl.usage_state["available"] = True     # as if the collector answered
        reads = [self.clock.now + timedelta(seconds=i + 1) for i in range(3)]
        self.clock.advance(5)
        self.ctl.process(self.cfg.secret("api-key/demo"), self.clock.now, reads, set())
        md = self.md()
        self.assertEqual(md.current_version, 2)
        self.assertEqual(h.decode(md.custom)[2].trigger, "usage")
        self.assertEqual(md.custom[h.READS_SINCE], "0")
        # the same reads (older than the cursor) are not counted again
        self.ctl.process(self.cfg.secret("api-key/demo"), self.clock.now, reads, set())
        self.assertEqual(self.md().current_version, 2)

    def test_cas_conflict_is_a_skip(self):
        self.ctl.loop_once()
        md = self.md()
        self.vault.foreign_write("shift-gear/rotation/api-key/demo", "x" * 40)   # someone else wrote v2
        self.ctl.rotate(self.cfg.secret("api-key/demo"), md, triggers.Trigger("time", "t", "schedule"), {})
        self.assertEqual(self.ctl.counters["cas_skips"], 1)
        self.assertEqual(self.md().current_version, 2)

    def test_crash_between_write_and_record_is_recovered(self):
        self.ctl.loop_once()
        self.vault.fail_patch_once = True
        self.clock.advance(61)
        self.ctl.loop_once()                       # write succeeds, record patch fails
        self.assertEqual(self.md().current_version, 2)
        self.assertNotIn(2, h.decode(self.md().custom))
        self.ctl.loop_once()                       # next loop recovers v2
        rec = h.decode(self.md().custom)[2]
        self.assertEqual(rec.trigger, "recovered")
        self.assertEqual(rec.fingerprint, fingerprint(self.vault.read_value("shift-gear/rotation/api-key/demo", 2)))

    def test_reconcile_enforces_settings(self):
        self.ctl.loop_once()
        self.vault.patch_metadata("shift-gear/rotation/api-key/demo", {h.TYPE: "tampered"},
                                  max_versions=99, cas_required=False)
        self.ctl.loop_once()
        md = self.md()
        self.assertEqual((md.max_versions, md.cas_required, md.custom[h.TYPE]), (5, True, "api-key"))
        self.assertIn('"msg": "enforced"', self.log_stream.getvalue())

    def test_history_pruned_to_max_versions(self):
        self.ctl.loop_once()
        for _ in range(8):
            self.clock.advance(61)
            self.ctl.loop_once()
        md = self.md()
        self.assertEqual(md.current_version, 9)
        self.assertEqual(sorted(h.decode(md.custom)), [5, 6, 7, 8, 9])

    def test_values_never_logged_or_published(self):
        self.ctl.loop_once()
        self.clock.advance(61)
        self.ctl.loop_once()
        values = [v["value"] for e in self.vault.entries.values() for v in e["versions"].values()]
        output = self.log_stream.getvalue() + json.dumps(self.ctl.snapshot()) + json.dumps(self.ctl.compliance_report())
        for value in values:
            if value in ("core", "core2"):
                continue
            self.assertNotIn(value, output)

    def test_redaction_canary(self):
        canary = "CANARY-" + "q" * 32
        REGISTRY.add(canary)
        self.logger.error("failure with %s inside", canary)
        try:
            raise RuntimeError(f"boom {canary}")
        except RuntimeError:
            self.logger.exception("loop failed")
        self.assertNotIn(canary, self.log_stream.getvalue())
        self.assertIn("<redacted>", self.log_stream.getvalue())

    def test_compliance(self):
        self.ctl.loop_once()
        report = self.ctl.compliance_report()
        self.assertEqual(report["summary"]["compliant"], report["summary"]["total"])
        self.clock.advance(400)                    # past api-key max_age (5m), controller "down"
        demo = compliance.evaluate(self.cfg.secret("api-key/demo"), self.cfg, self.md(), self.clock.now)
        self.assertFalse(demo["compliant"])
        self.assertTrue(any(r.startswith("overdue") for r in demo["reasons"]))
        self.vault.foreign_write("shift-gear/rotation/api-key/demo", "y" * 40)
        demo = compliance.evaluate(self.cfg.secret("api-key/demo"), self.cfg, self.md(), self.clock.now)
        self.assertTrue(any("no rotation record" in r for r in demo["reasons"]))
        missing = compliance.evaluate(self.cfg.secret("api-key/demo"), self.cfg, None, self.clock.now)
        self.assertIn("not onboarded", missing["reasons"][0])

    def test_status_shape(self):
        self.ctl.loop_once()
        snap = self.ctl.snapshot()
        self.assertEqual(snap["controller"]["events"], "polling")
        self.assertEqual({s["secret"] for s in snap["secrets"]}, {"api-key/demo", "signing-key/session-signing"})
        self.assertTrue(self.ctl.healthy())


class TimeParsingTests(unittest.TestCase):
    def test_nanoseconds(self):
        t = parse_time("2026-10-28T10:31:10.925123456Z")
        self.assertEqual(t.microsecond, 925123)
        self.assertEqual(parse_time(iso_precise(t)), t)
        self.assertIsNone(parse_time(None))


class StdlibOnlyTests(unittest.TestCase):
    def test_runtime_imports_are_stdlib(self):
        allowed = set(sys.stdlib_module_names) | {"rotation"}
        pkg = HERE.parent / "rotation"
        for py in pkg.glob("*.py"):
            tree = ast.parse(py.read_text())
            for node in ast.walk(tree):
                names = []
                if isinstance(node, ast.Import):
                    names = [a.name for a in node.names]
                elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                    names = [node.module]
                for name in names:
                    top = name.split(".")[0]
                    if top == "yaml":
                        continue          # optional, host CLI only (guarded import)
                    self.assertIn(top, allowed, f"{py.name} imports third-party '{name}'")


if __name__ == "__main__":
    unittest.main()
