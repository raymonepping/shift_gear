"""Rotation history in KV v2 custom metadata.

Per retained version the controller writes one key, v<N>, holding
    <fp12>|<trigger>|<iso-time>|<actor>
Summary keys carry the current state. Custom metadata allows 64 keys of up
to 512 bytes each; config.py caps max_versions at 50 to leave room.
"""
from __future__ import annotations

from dataclasses import dataclass

# Summary keys (all non-secret).
MANAGED_BY = "rotation_managed_by"
TYPE = "rotation_type"
STRATEGIES = "rotation_strategies"
LAST_ROTATED = "rotation_last_rotated"
LAST_TRIGGER = "rotation_last_trigger"
READS_SINCE = "rotation_reads_since"
READS_CURSOR = "rotation_reads_cursor"
REQUEST = "rotation_request"            # written by humans: <uuid>|<actor>|<reason>
SERVED = "rotation_request_served"      # last served request uuid
WATCH = "rotation_watch"                # <path>@<version>[,<path>@<version>...]
MANAGED_BY_VALUE = "kv-rotation-controller"

TRIGGERS = ("created", "time", "usage", "request", "event", "recovered")


def _clean(text: str, limit: int) -> str:
    return "".join(ch for ch in str(text) if ch not in "|\n\r")[:limit]


@dataclass(frozen=True)
class Record:
    version: int
    fingerprint: str
    trigger: str
    at: str
    actor: str

    def encode(self) -> str:
        return "|".join([_clean(self.fingerprint, 12), _clean(self.trigger, 120),
                         _clean(self.at, 25), _clean(self.actor, 120)])


def key(version: int) -> str:
    return f"v{version}"


def decode(custom: dict[str, str]) -> dict[int, Record]:
    records: dict[int, Record] = {}
    for name, raw in custom.items():
        if not (name.startswith("v") and name[1:].isdigit()) or not isinstance(raw, str):
            continue
        parts = raw.split("|")
        if len(parts) != 4:
            continue
        version = int(name[1:])
        records[version] = Record(version, parts[0], parts[1], parts[2], parts[3])
    return records


def prune_keys(custom: dict[str, str], current_version: int, max_versions: int) -> dict[str, None]:
    """Keys of versions KV v2 no longer retains -> None (merge-patch removal)."""
    oldest_kept = current_version - max_versions + 1
    return {name: None for version, rec in decode(custom).items()
            if version < oldest_kept for name in [key(version)]}


def parse_request(raw: str | None) -> tuple[str, str, str] | None:
    """'<uuid>|<actor>|<reason>' -> (uuid, actor, reason); tolerant of missing parts."""
    if not raw:
        return None
    parts = (raw.split("|") + ["", ""])[:3]
    request_id = parts[0].strip()
    if not request_id:
        return None
    return request_id, _clean(parts[1] or "unknown", 120), _clean(parts[2], 200)


def encode_request(request_id: str, actor: str, reason: str) -> str:
    return "|".join([_clean(request_id, 64), _clean(actor, 120), _clean(reason, 200)])


def parse_watch(raw: str | None) -> dict[str, int]:
    out: dict[str, int] = {}
    for item in (raw or "").split(","):
        if "@" in item:
            path, _, version = item.rpartition("@")
            if version.isdigit():
                out[path] = int(version)
    return out


def encode_watch(watch: dict[str, int]) -> str:
    return ",".join(f"{path}@{version}" for path, version in sorted(watch.items()))
