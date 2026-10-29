"""The Secure Door — a fictional verifier, clearly labelled as such.

It reads the *latest complete Agent snapshot* itself, independently of the
consumer's cached credential, and compares in constant time. What GRANTED
proves: the presented credential equals Vault's latest version as last
rendered by the Agent. What it does NOT prove: that any external service
validated, rejected or revoked anything — no issuer exists.
"""
from __future__ import annotations

import hmac
from dataclasses import dataclass

from . import snapshot

MEANING = {
    "GRANTED": "cached credential matches Vault's latest version (no issuer exists)",
    "DENIED": "cached credential differs from Vault's latest version (no issuer exists)",
}


@dataclass(frozen=True)
class Verdict:
    verdict: str            # GRANTED | DENIED | UNAVAILABLE
    checked_version: int | None   # the snapshot version the door compared against
    reason: str = ""

    @property
    def meaning(self) -> str:
        return MEANING.get(self.verdict, self.reason)


class SecureDoor:
    def __init__(self, snapshot_path: str):
        self.snapshot_path = snapshot_path

    def check(self, presented: str) -> Verdict:
        """Compare a presented credential with the newest rendered value."""
        if not isinstance(presented, str) or len(presented) < 16:
            # A fingerprint (12 hex) or anything short is never a credential.
            return Verdict("DENIED", None, "not a credential")
        try:
            current = snapshot.read(self.snapshot_path)
        except (snapshot.SnapshotMissing, snapshot.SnapshotInvalid) as exc:
            return Verdict("UNAVAILABLE", None, f"no complete snapshot ({exc.__class__.__name__})")
        ok = hmac.compare_digest(presented.encode(), current.value.encode())
        return Verdict("GRANTED" if ok else "DENIED", current.version)
