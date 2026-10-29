"""Tail the NDJSON stream written by the vault-events sidecar.

`vault events subscribe -format=json 'kv-v2/*'` prints one JSON object per
event. The secret's API path is in data.event.metadata.path (for example
"kv/data/shift-gear/config/app-config"). Events only make the controller
react faster: every decision is re-derived from Vault metadata, so a missed
event is late, never lost.
"""
from __future__ import annotations

import json
import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Event:
    event_type: str
    rel_path: str      # mount-relative, e.g. shift-gear/config/app-config
    mount_path: str    # the API path as reported


def normalise(path: str, mount: str) -> str | None:
    """'shift-gear/kv/data/x' or 'kv/metadata/x' -> 'x' (None if not this mount)."""
    parts = path.strip("/").split("/")
    mount = mount.strip("/")
    for i in range(len(parts) - 1):
        if parts[i] == mount and parts[i + 1] in ("data", "metadata", "delete", "undelete", "destroy"):
            rest = "/".join(parts[i + 2:])
            return rest or None
    return None


def parse_line(line: str, mount: str) -> Event | None:
    try:
        obj = json.loads(line)
    except ValueError:
        return None
    if not isinstance(obj, dict):
        return None
    data = obj.get("data") if isinstance(obj.get("data"), dict) else obj
    event_type = str(data.get("event_type") or obj.get("event_type") or "")
    event = data.get("event") if isinstance(data.get("event"), dict) else {}
    metadata = event.get("metadata") if isinstance(event.get("metadata"), dict) else {}
    raw_path = str(metadata.get("path") or metadata.get("data_path") or "")
    if not event_type or not raw_path:
        return None
    rel = normalise(raw_path, mount)
    if rel is None:
        return None
    return Event(event_type=event_type, rel_path=rel, mount_path=raw_path)


class EventTail:
    def __init__(self, path: str, mount: str):
        self.path = path
        self.mount = mount
        self._offset = 0
        self._inode: int | None = None
        self.lines_seen = 0

    @property
    def available(self) -> bool:
        return bool(self.path) and os.path.exists(self.path)

    def read(self) -> list[Event]:
        if not self.available:
            return []
        stat = os.stat(self.path)
        if self._inode != stat.st_ino or stat.st_size < self._offset:
            self._offset, self._inode = 0, stat.st_ino      # rotated or truncated
        events: list[Event] = []
        with open(self.path, "r", encoding="utf-8", errors="replace") as handle:
            handle.seek(self._offset)
            for line in handle:
                if not line.endswith("\n"):
                    break                                   # partial line: read it next time
                self._offset += len(line.encode("utf-8"))
                self.lines_seen += 1
                parsed = parse_line(line, self.mount)
                if parsed is not None:
                    events.append(parsed)
        return events
