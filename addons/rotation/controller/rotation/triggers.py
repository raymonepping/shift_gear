"""Pure trigger decisions: which strategy (if any) says "rotate now"."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime

from .config import Secret

# Highest first: a human asked > something changed > it was used > it is old.
PRIORITY = ("request", "event", "usage", "time")


@dataclass(frozen=True)
class State:
    """What Vault says about one managed secret right now."""
    last_rotated: datetime | None          # created_time of the current version
    reads_since: int | None                # None = not reported
    pending_request: tuple[str, str, str] | None = None   # (uuid, actor, reason), not yet served
    changed_watches: tuple[str, ...] = field(default_factory=tuple)  # watched paths with a newer version


@dataclass(frozen=True)
class Trigger:
    kind: str       # request | event | usage | time
    detail: str     # human-readable, non-secret
    actor: str      # who/what caused it
    request_id: str | None = None


def due(secret: Secret, state: State, now: datetime) -> list[Trigger]:
    """Every trigger that currently applies, highest priority first."""
    found: list[Trigger] = []
    if "event" in secret.strategies and state.pending_request:
        request_id, actor, reason = state.pending_request
        found.append(Trigger("request", reason or "rotation requested", actor or "unknown", request_id))
    if "event" in secret.strategies and state.changed_watches:
        found.append(Trigger("event", f"{', '.join(state.changed_watches)} written", "vault-event"))
    if ("usage" in secret.strategies and secret.max_reads is not None
            and state.reads_since is not None and state.reads_since >= secret.max_reads):
        found.append(Trigger("usage", f"{state.reads_since} reads >= {secret.max_reads}", "usage-policy"))
    if "time" in secret.strategies and state.last_rotated is not None:
        age = (now - state.last_rotated).total_seconds()
        if age >= secret.interval:
            found.append(Trigger("time", f"age {int(age)}s >= interval {secret.interval}s", "schedule"))
    found.sort(key=lambda t: PRIORITY.index(t.kind))
    return found


def decide(secret: Secret, state: State, now: datetime) -> Trigger | None:
    """One rotation even if several triggers apply; the recorded reason is the highest priority."""
    triggers = due(secret, state, now)
    return triggers[0] if triggers else None


def next_due(secret: Secret, state: State) -> dict[str, object]:
    """When each strategy will fire next (for /status and the UI)."""
    out: dict[str, object] = {}
    if "time" in secret.strategies and state.last_rotated is not None:
        out["time"] = state.last_rotated.timestamp() + secret.interval
    if "usage" in secret.strategies and secret.max_reads is not None:
        out["usage_reads_left"] = (None if state.reads_since is None
                                   else max(0, secret.max_reads - state.reads_since))
    if "event" in secret.strategies:
        out["event"] = [e.path for e in secret.events] or "on request"
    return out
