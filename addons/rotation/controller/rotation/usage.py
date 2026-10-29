"""Usage counting from the Vault audit stream (via the sg-audit collector).

Every Vault operation reaches the collector twice (request + response). A
read of a managed secret is one entry with type=request, operation=read,
path=<mount>/data/<rel>, no error. Entries are de-duplicated on their audit
id. The controller's own reads (it compares fingerprints) are excluded by
display name. When the collector dropped entries since the last poll, the
counts are flagged as possibly undercounted rather than presented as exact.
"""
from __future__ import annotations

import json
import urllib.error
import urllib.request
from collections import OrderedDict
from dataclasses import dataclass, field
from datetime import datetime

from .vault import parse_time


@dataclass
class Poll:
    reads: dict[str, list[datetime]] = field(default_factory=dict)   # rel_path -> read times
    undercount: bool = False
    available: bool = True
    reason: str = ""


class UsageCounter:
    def __init__(self, audit_url: str, mount: str, namespace: str, timeout: float = 3.0):
        self.audit_url = audit_url.rstrip("/")
        self.mount = mount.strip("/")
        self.namespace = namespace.strip("/") + "/" if namespace else ""
        self.timeout = timeout
        self.exclude_display_names: set[str] = set()
        self._seen: OrderedDict[str, None] = OrderedDict()
        self._last_dropped: int | None = None
        self._last_instance: str | None = None

    def _remember(self, entry_id: str) -> bool:
        """True if new. Bounded memory."""
        if entry_id in self._seen:
            return False
        self._seen[entry_id] = None
        while len(self._seen) > 20000:
            self._seen.popitem(last=False)
        return True

    def fetch(self) -> dict:
        req = urllib.request.Request(f"{self.audit_url}/audit?limit=500")
        with urllib.request.urlopen(req, timeout=self.timeout) as resp:
            return json.load(resp)

    def poll(self, managed: set[str], payload: dict | None = None) -> Poll:
        if payload is None:
            try:
                payload = self.fetch()
            except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
                return Poll(available=False, reason=f"collector unreachable ({exc.__class__.__name__})")
        return self.count(payload, managed)

    def count(self, payload: dict, managed: set[str]) -> Poll:
        result = Poll()
        collector = payload.get("collector") or {}
        dropped = int(collector.get("dropped") or 0)
        instance = str(collector.get("instanceId") or "")
        if self._last_instance is not None and instance != self._last_instance:
            result.undercount = True       # collector restarted: entries in between are gone
        elif self._last_dropped is not None and dropped > self._last_dropped:
            result.undercount = True
        self._last_dropped, self._last_instance = dropped, instance

        prefix = f"{self.mount}/data/"
        for entry in payload.get("entries") or []:
            if entry.get("type") != "request" or entry.get("operation") != "read" or entry.get("error"):
                continue
            if self.namespace and entry.get("namespace") != self.namespace:
                continue
            path = str(entry.get("path") or "")
            if not path.startswith(prefix):
                continue
            rel = path[len(prefix):]
            if rel not in managed:
                continue
            if entry.get("displayName") in self.exclude_display_names:
                continue
            entry_id = str(entry.get("id") or "")
            if not entry_id or not self._remember(entry_id):
                continue
            at = parse_time(entry.get("time"))
            if at is not None:
                result.reads.setdefault(rel, []).append(at)
        return result
