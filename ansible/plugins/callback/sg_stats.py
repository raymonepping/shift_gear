# Copyright: shift_gear. GPLv3.
"""Write only the play recap counts of a shift_gear phase to a JSON file.

Never task results, never variables: one row per host with ok / changed /
failures / unreachable / skipped / rescued / ignored, plus the phase name,
whether it ran in check mode, and when. `make idempotency` and `make drift`
read these files; so does the console's Layers page (via .build/layers.json).

Ported from golden_ticket's gt_stats callback. Only the class name, env vars,
and output prefix changed.
"""

from __future__ import annotations

DOCUMENTATION = """
name: sg_stats
type: aggregate
short_description: Write the play recap counts (only) of a shift_gear phase
description:
  - At the end of a run, writes <SG_STATS_DIR>/<SG_PHASE>[.check].json with the
    per-host recap counts. Does nothing unless both SG_PHASE and SG_STATS_DIR
    are set (so Terraform-run baselines write nothing).
requirements:
  - enable in callbacks_enabled
"""

import datetime
import json
import os

try:
    from ansible import context as _ansible_context
    from ansible.plugins.callback import CallbackBase as _CallbackBase
    _ANSIBLE_AVAILABLE = True
except ImportError:  # allow unit tests to import without full ansible runtime
    _ansible_context = None   # type: ignore[assignment]
    _CallbackBase = object    # type: ignore[assignment,misc]
    _ANSIBLE_AVAILABLE = False

COUNTERS = ("ok", "changed", "failures", "unreachable", "skipped", "rescued", "ignored")


def summarize(stats):
    """Per-host recap counts from an AggregateStats-like object."""
    hosts = {}
    for host in sorted(stats.processed):
        counts = stats.summarize(host)
        hosts[host] = {key: int(counts.get(key, 0)) for key in COUNTERS}
    return hosts


def write_stats(out_dir, phase, hosts, check_mode, now=None):
    """Write the stats file atomically; return its path."""
    now = now or datetime.datetime.now(datetime.timezone.utc)
    document = {
        "phase": phase,
        "check_mode": bool(check_mode),
        "finished_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "hosts": hosts,
        "changed_total": sum(h["changed"] for h in hosts.values()),
        "failed_total": sum(h["failures"] + h["unreachable"] for h in hosts.values()),
    }
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{phase}{'.check' if check_mode else ''}.json")
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(document, handle, indent=2, sort_keys=True)
        handle.write("\n")
    os.replace(tmp, path)
    return path


class CallbackModule(_CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "aggregate"
    CALLBACK_NAME = "sg_stats"
    CALLBACK_NEEDS_ENABLED = True

    def v2_playbook_on_stats(self, stats):
        phase = os.environ.get("SG_PHASE")
        out_dir = os.environ.get("SG_STATS_DIR")
        if not phase or not out_dir:
            return
        check_mode = bool(
            _ansible_context.CLIARGS.get("check", False)  # type: ignore[union-attr]
            if _ANSIBLE_AVAILABLE and _ansible_context else False
        )
        write_stats(out_dir, phase, summarize(stats), check_mode)
