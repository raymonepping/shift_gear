"""Health signals, kept apart (prompt 01_09, "Health signals").

- Vault connectivity: the vault-probe container's unauthenticated `vault status`
  result in /health/vault.json. Reachability only — not proof the Agent may read.
- Last successful Vault refresh: positive Agent-side evidence only — a template
  fetch success line in the Agent's own log file, *if* the deployed Agent writes
  one. Otherwise "not observable".
- Fetch errors: Agent log lines reporting a failed template read.
No signal is ever inferred from the age of the rendered file: the Agent only
rewrites it when the secret changes.
"""
from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone

# consul-template (inside Vault Agent) at TRACE level logs a successful read of a
# dependency as "... marking successful data response"; failures as errors on
# the view/runner. Both patterns are verified live in 01_09's execution log.
_SUCCESS_LINE = re.compile(r"successful data response", re.IGNORECASE)
_ERROR_LINE = re.compile(r"\[(ERROR|WARN)\].*(view|runner|template|kv\.read|vault\.read)", re.IGNORECASE)
_TIME = re.compile(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)")


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def iso(moment: datetime | None) -> str | None:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if moment else None


def parse_time(text: str | None) -> datetime | None:
    if not text:
        return None
    t = text.strip().replace("Z", "+00:00")
    if "." in t:
        head, tail = t.split(".", 1)
        frac = "".join(ch for ch in tail if ch.isdigit())
        rest = tail[len(frac):]
        t = f"{head}.{frac[:6].ljust(6, '0')}{rest}"
    try:
        out = datetime.fromisoformat(t)
    except ValueError:
        return None
    return out if out.tzinfo else out.replace(tzinfo=timezone.utc)


@dataclass
class VaultProbe:
    state: str = "unknown"          # reachable | unreachable | sealed | unknown
    at: datetime | None = None
    since: datetime | None = None   # when the current state began
    detail: str = ""


def read_probe(path: str, previous: VaultProbe, max_age_s: float) -> VaultProbe:
    """The probe writes {"reachable": bool, "sealed": bool|null, "rc": int, "at": iso}."""
    try:
        with open(path, "rb") as handle:
            doc = json.loads(handle.read(4096))
    except (OSError, ValueError):
        return VaultProbe("unknown", previous.at, previous.since if previous.state == "unknown" else utcnow(),
                          "no probe result")
    at = parse_time(doc.get("at"))
    if at is None or (utcnow() - at).total_seconds() > max_age_s:
        state, detail = "unknown", "probe result too old"
    elif not doc.get("reachable"):
        state, detail = "unreachable", f"vault status rc={doc.get('rc')}"
    elif doc.get("sealed"):
        state, detail = "sealed", "vault reports sealed"
    else:
        state, detail = "reachable", "unsealed"
    since = previous.since if previous.state == state and previous.since else utcnow()
    return VaultProbe(state, at, since, detail)


@dataclass
class AgentEvidence:
    observable: bool = False
    last_refresh: datetime | None = None
    last_error: str | None = None
    last_error_at: datetime | None = None
    _offset: int = field(default=0, repr=False)
    _inode: int | None = field(default=None, repr=False)


def scan_agent_log(path: str, ev: AgentEvidence) -> AgentEvidence:
    """Tail the Agent's log file for refresh successes and fetch errors."""
    try:
        stat = os.stat(path)
    except OSError:
        return ev
    if ev._inode != stat.st_ino or stat.st_size < ev._offset:
        ev._offset, ev._inode = 0, stat.st_ino
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        handle.seek(ev._offset)
        for line in handle:
            if not line.endswith("\n"):
                break
            ev._offset += len(line.encode("utf-8"))
            stamp = _TIME.match(line)
            when = parse_time(stamp.group(1)) if stamp else utcnow()
            if _SUCCESS_LINE.search(line):
                ev.observable = True
                ev.last_refresh = when
            elif _ERROR_LINE.search(line):
                # Keep only the event class, never the line (it could carry a path or worse).
                ev.last_error = "template fetch error reported by the Agent"
                ev.last_error_at = when
    return ev
