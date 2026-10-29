"""The Secure Door request protocol — no secret crosses the network.

The client proves possession of the shared secret for a given KV version:

    payload = "secure-door|<client-id>|<ts>|<nonce>"
    sig     = hex(HMAC-SHA256(secret_v, payload))
    request = {"client": id, "key_version": v, "ts": ts, "nonce": nonce, "sig": sig}

The verifier refuses a request outside the timestamp window, a nonce it has
already seen inside that window (replay), a key version it does not hold, and
a bad signature — and says which.
"""
from __future__ import annotations

import hashlib
import hmac
import secrets
import threading
import time
from collections import OrderedDict

WINDOW_S = 30          # acceptable |now - ts|; nonces are remembered at least this long
NONCE_BYTES = 16


def payload(client: str, ts: int, nonce: str) -> bytes:
    return f"secure-door|{client}|{ts}|{nonce}".encode()


def sign(secret: str, client: str, ts: int, nonce: str) -> str:
    return hmac.new(secret.encode(), payload(client, ts, nonce), hashlib.sha256).hexdigest()


def new_request(secret: str, version: int, client: str, now: float | None = None) -> dict:
    ts = int(now if now is not None else time.time())
    nonce = secrets.token_hex(NONCE_BYTES)
    return {"client": client, "key_version": version, "ts": ts, "nonce": nonce,
            "sig": sign(secret, client, ts, nonce)}


class NonceCache:
    """Nonces seen within the window; bounded memory, thread-safe."""

    def __init__(self, window_s: int = WINDOW_S, limit: int = 100_000):
        self.window_s = window_s
        self.limit = limit
        self._seen: OrderedDict[str, float] = OrderedDict()
        self._lock = threading.Lock()

    def seen_before(self, nonce: str, now: float) -> bool:
        """Record the nonce; True if it was already recorded inside the window."""
        with self._lock:
            cutoff = now - 2 * self.window_s
            while self._seen and next(iter(self._seen.values())) < cutoff:
                self._seen.popitem(last=False)
            if nonce in self._seen:
                return True
            self._seen[nonce] = now
            while len(self._seen) > self.limit:
                self._seen.popitem(last=False)
            return False


def check_shape(req: object) -> str | None:
    """A reason the request is malformed, or None."""
    if not isinstance(req, dict):
        return "malformed"
    if not isinstance(req.get("client"), str) or not 1 <= len(req["client"]) <= 64:
        return "malformed"
    if not isinstance(req.get("key_version"), int) or isinstance(req.get("key_version"), bool):
        return "malformed"
    if not isinstance(req.get("ts"), int) or isinstance(req.get("ts"), bool):
        return "malformed"
    nonce, sig = req.get("nonce"), req.get("sig")
    if not isinstance(nonce, str) or len(nonce) != 2 * NONCE_BYTES or any(c not in "0123456789abcdef" for c in nonce):
        return "malformed"
    if not isinstance(sig, str) or len(sig) != 64 or any(c not in "0123456789abcdef" for c in sig):
        return "malformed"
    return None
