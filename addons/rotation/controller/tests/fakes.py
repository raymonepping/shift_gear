"""An in-memory KV v2 with check-and-set and merge-patch semantics."""
from __future__ import annotations

import copy
from datetime import datetime, timedelta, timezone

from rotation.vault import CasConflict, Metadata, VaultError, iso_precise


class FakeClock:
    def __init__(self, start: datetime | None = None):
        self.now = start or datetime(2026, 10, 28, 10, 0, 0, tzinfo=timezone.utc)

    def advance(self, seconds: float) -> None:
        self.now += timedelta(seconds=seconds)


class FakeVault:
    def __init__(self, clock: FakeClock, display_name: str = "shift-gear-auth-kubernetes-rotation-controller"):
        self.clock = clock
        self.display_name = display_name
        self.entries: dict[str, dict] = {}     # rel -> {"meta": {...}, "versions": {n: {...}}}
        self.writes: list[tuple[str, int]] = []
        self.fail_patch_once = False

    def _entry(self, rel: str) -> dict:
        return self.entries.setdefault(rel, {"meta": {"max_versions": 0, "cas_required": False,
                                                      "custom_metadata": {}, "current_version": 0},
                                             "versions": {}})

    def read_metadata(self, rel: str) -> Metadata | None:
        if rel not in self.entries:
            return None
        e = self.entries[rel]
        data = copy.deepcopy(e["meta"])
        data["versions"] = {str(n): {"created_time": iso_precise(v["created"]), "destroyed": False}
                            for n, v in e["versions"].items()}
        data["updated_time"] = iso_precise(self.clock.now)
        return Metadata.from_api(data)

    def write_metadata(self, rel, max_versions, cas_required, custom):
        e = self._entry(rel)
        e["meta"].update(max_versions=max_versions, cas_required=cas_required, custom_metadata=dict(custom))

    def patch_metadata(self, rel, custom=None, token=None, **settings):
        if self.fail_patch_once:
            self.fail_patch_once = False
            raise VaultError(500, rel, ["injected"])
        e = self._entry(rel)
        e["meta"].update(settings)
        if custom:
            cm = e["meta"]["custom_metadata"]
            for k, v in custom.items():
                if v is None:
                    cm.pop(k, None)
                else:
                    cm[k] = v

    def write_value(self, rel, value, cas):
        e = self._entry(rel)
        current = e["meta"]["current_version"]
        if (e["meta"].get("cas_required") or cas is not None) and cas != current:
            raise CasConflict(400, rel, ["check-and-set parameter did not match the current version"])
        version = current + 1
        e["versions"][version] = {"value": value, "created": self.clock.now}
        e["meta"]["current_version"] = version
        keep = e["meta"].get("max_versions") or 10
        for old in [n for n in e["versions"] if n <= version - keep]:
            del e["versions"][old]
        self.writes.append((rel, version))
        return version

    def foreign_write(self, rel, value):
        """A write that bypasses the controller (no record)."""
        e = self._entry(rel)
        return self.write_value(rel, value, e["meta"]["current_version"])

    def read_value(self, rel, version=None):
        e = self.entries.get(rel)
        if not e:
            return None
        n = version or e["meta"]["current_version"]
        return (e["versions"].get(n) or {}).get("value")

    def list_metadata(self, rel):
        prefix = rel.rstrip("/") + "/"
        keys = set()
        for path in self.entries:
            if path.startswith(prefix):
                rest = path[len(prefix):]
                keys.add(rest.split("/")[0] + "/" if "/" in rest else rest)
        return sorted(keys)

    def lookup_self(self):
        return {"display_name": self.display_name, "policies": ["sg-rotation-controller"]}
