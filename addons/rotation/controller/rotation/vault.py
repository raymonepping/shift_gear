"""Minimal KV v2 client over HTTP (standard library).

In the cluster the controller talks to its vault-agent sidecar's api_proxy on
loopback (no token in this process; the agent injects it). The host CLI
talks to Vault directly with a token and the project CA.
"""
from __future__ import annotations

import json
import ssl
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone


class VaultError(RuntimeError):
    def __init__(self, status: int, path: str, errors: list[str] | None = None):
        # Never include request bodies: they may carry a value.
        super().__init__(f"vault {status} on {path}: {'; '.join(errors or []) or 'no detail'}")
        self.status = status
        self.path = path
        self.errors = errors or []


class CasConflict(VaultError):
    """Someone else wrote a version since we read the metadata."""


class Unreachable(RuntimeError):
    """The proxy/Vault did not answer (sealed, restarting, agent not ready)."""


def parse_time(value: str | None) -> datetime | None:
    """Vault RFC3339 with nanoseconds -> aware datetime (microsecond precision)."""
    if not value:
        return None
    text = value.strip().replace("Z", "+00:00")
    if "." in text:
        head, tail = text.split(".", 1)
        frac = ""
        offset = ""
        for i, ch in enumerate(tail):
            if not ch.isdigit():
                offset = tail[i:]
                break
            frac += ch
        text = f"{head}.{frac[:6].ljust(6, '0')}{offset}"
    parsed = datetime.fromisoformat(text)
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def iso(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def iso_precise(moment: datetime) -> str:
    """Microsecond precision, for cursors compared with audit entry times."""
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


@dataclass
class Metadata:
    current_version: int
    max_versions: int
    cas_required: bool
    custom: dict[str, str]
    versions: dict[int, dict]          # version -> {created_time, deletion_time, destroyed}
    updated_time: datetime | None

    def created(self, version: int) -> datetime | None:
        info = self.versions.get(version) or {}
        return parse_time(info.get("created_time"))

    @classmethod
    def from_api(cls, data: dict) -> "Metadata":
        return cls(
            current_version=int(data.get("current_version") or 0),
            max_versions=int(data.get("max_versions") or 0),
            cas_required=bool(data.get("cas_required")),
            custom=dict(data.get("custom_metadata") or {}),
            versions={int(k): v for k, v in (data.get("versions") or {}).items()},
            updated_time=parse_time(data.get("updated_time")),
        )


class Vault:
    def __init__(self, address: str, namespace: str, mount: str, token: str | None = None,
                 cafile: str | None = None, timeout: float = 10.0):
        self.address = address.rstrip("/")
        self.namespace = namespace
        self.mount = mount.strip("/")
        self._token = token
        self.timeout = timeout
        self._ctx = ssl.create_default_context(cafile=cafile) if self.address.startswith("https") else None

    # -- transport ---------------------------------------------------------
    def request(self, method: str, path: str, body: dict | None = None,
                content_type: str = "application/json", token: str | None = None) -> dict:
        headers = {"Content-Type": content_type}
        if self.namespace:
            headers["X-Vault-Namespace"] = self.namespace
        if token or self._token:
            headers["X-Vault-Token"] = token or self._token  # type: ignore[assignment]
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(f"{self.address}/v1/{path}", data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, context=self._ctx, timeout=self.timeout) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            try:
                errors = json.loads(exc.read() or b"{}").get("errors") or []
            except (ValueError, AttributeError):
                errors = []
            if exc.code == 400 and any("check-and-set" in e for e in errors):
                raise CasConflict(exc.code, path, errors) from None
            raise VaultError(exc.code, path, errors) from None
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as exc:
            raise Unreachable(f"{path}: {exc.__class__.__name__}") from None

    # -- KV v2 -------------------------------------------------------------
    def read_metadata(self, rel: str) -> Metadata | None:
        try:
            return Metadata.from_api(self.request("GET", f"{self.mount}/metadata/{rel}").get("data") or {})
        except VaultError as exc:
            if exc.status == 404:
                return None
            raise

    def write_metadata(self, rel: str, max_versions: int, cas_required: bool, custom: dict[str, str]) -> None:
        self.request("POST", f"{self.mount}/metadata/{rel}",
                     {"max_versions": max_versions, "cas_required": cas_required, "custom_metadata": custom})

    def patch_metadata(self, rel: str, custom: dict[str, str | None] | None = None,
                       token: str | None = None, **settings) -> None:
        """JSON merge patch; a custom_metadata key set to None is removed."""
        body: dict = dict(settings)
        if custom is not None:
            body["custom_metadata"] = custom
        self.request("PATCH", f"{self.mount}/metadata/{rel}", body,
                     content_type="application/merge-patch+json", token=token)

    def write_value(self, rel: str, value: str, cas: int) -> int:
        """Write {value} as a new version with check-and-set; returns the new version."""
        data = self.request("POST", f"{self.mount}/data/{rel}", {"options": {"cas": cas}, "data": {"value": value}})
        return int((data.get("data") or {}).get("version") or 0)

    def read_value(self, rel: str, version: int | None = None) -> str | None:
        suffix = f"?version={version}" if version else ""
        try:
            data = self.request("GET", f"{self.mount}/data/{rel}{suffix}").get("data") or {}
        except VaultError as exc:
            if exc.status == 404:
                return None
            raise
        return (data.get("data") or {}).get("value")

    def list_metadata(self, rel: str) -> list[str]:
        try:
            return list((self.request("LIST", f"{self.mount}/metadata/{rel}").get("data") or {}).get("keys") or [])
        except VaultError as exc:
            if exc.status == 404:
                return []
            raise

    def lookup_self(self) -> dict:
        return self.request("GET", "auth/token/lookup-self").get("data") or {}
