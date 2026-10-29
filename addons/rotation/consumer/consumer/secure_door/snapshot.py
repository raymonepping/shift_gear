"""The Agent-rendered snapshot: one JSON document per KV v2 read.

The Agent template renders `{{ .Data | toJSON }}` of a KV v2 secret, i.e.
{"data": {"value": "..."}, "metadata": {"version": N, "created_time": "..."}}.
Only a complete, well-formed document is ever accepted; anything else is a
distinct, named condition — never a half-read credential.
"""
from __future__ import annotations

import hashlib
import json
import os
from dataclasses import dataclass, field


class SnapshotMissing(Exception):
    """No rendered file yet (Agent not authenticated, or first render pending)."""


class SnapshotInvalid(Exception):
    """The file exists but is not a complete, well-formed snapshot."""


@dataclass(frozen=True)
class Snapshot:
    version: int
    created_time: str | None
    value: str = field(repr=False)          # never in repr, logs or status
    mtime: float = 0.0

    @property
    def fingerprint(self) -> str:
        """Same fp12 as the rotation controller and `make rotation-history`."""
        return hashlib.sha256(self.value.encode()).hexdigest()[:12]

    def __str__(self) -> str:               # defensive: printing it never leaks
        return f"Snapshot(v{self.version}, fp={self.fingerprint})"


def read(path: str) -> Snapshot:
    try:
        stat = os.stat(path)
        with open(path, "rb") as handle:
            raw = handle.read(65536)
    except FileNotFoundError:
        raise SnapshotMissing(path) from None
    except OSError as exc:
        raise SnapshotInvalid(f"unreadable: {exc.__class__.__name__}") from None
    if not raw.strip():
        raise SnapshotInvalid("empty file")
    try:
        doc = json.loads(raw)
    except ValueError:
        raise SnapshotInvalid("not complete JSON") from None
    if not isinstance(doc, dict):
        raise SnapshotInvalid("not a JSON object")
    data = doc.get("data") if isinstance(doc.get("data"), dict) else None
    meta = doc.get("metadata") if isinstance(doc.get("metadata"), dict) else None
    if data is None or meta is None:
        raise SnapshotInvalid("missing data or metadata")
    value = data.get("value")
    version = meta.get("version")
    if not isinstance(value, str) or not value:
        raise SnapshotInvalid("no value field")
    if isinstance(version, bool) or not isinstance(version, int) or version < 1:
        raise SnapshotInvalid("no valid version")
    created = meta.get("created_time") if isinstance(meta.get("created_time"), str) else None
    return Snapshot(version=version, created_time=created, value=value, mtime=stat.st_mtime)
