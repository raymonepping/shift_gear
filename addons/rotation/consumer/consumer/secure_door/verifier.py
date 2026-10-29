"""door-verifier — the party that owns the trust decision.

It loads the shared secret from its *own* Vault Agent and keeps a key ring in
memory: the current version, plus (in grace mode) the previous version until
`adopted_at + DOOR_GRACE_SECONDS`. Strict mode (grace 0) retires the previous
version the moment a new one is adopted. Requests arrive on DOOR_ENTER_PORT
(8080, from the client only); status on DOOR_STATUS_PORT (9090, from the board).

The door is fictional; the trust decision is real: this process, with its own
identity and its own copy of the secret, accepts the new key and rejects the old.
"""
from __future__ import annotations

import hmac
import json
import signal
import threading
import time
from collections import Counter, OrderedDict, deque
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import protocol
from .health import iso, parse_time
from .party import Party


class Verifier(Party):
    role = "verifier"

    def __init__(self, env=None, out=None, clock=time.time):
        super().__init__(env, **({"out": out} if out else {}))
        self.grace_s = float(self.env.get("DOOR_GRACE_SECONDS", "30"))
        self.enter_port = int(self.env.get("DOOR_ENTER_PORT", "8080"))
        self.clock = clock
        self.ring: OrderedDict[int, dict] = OrderedDict()   # version -> {value, adopted_at, retire_at}
        self.current: int | None = None
        self.nonces = protocol.NonceCache()
        self.verdicts: Counter[str] = Counter()
        self.adoptions: deque[dict] = deque(maxlen=50)
        self.recent: deque[dict] = deque(maxlen=60)

    @property
    def mode(self) -> str:
        return "strict" if self.grace_s <= 0 else "grace"

    # -- the key ring -------------------------------------------------------------
    def adopt(self, version: int, value: str, created_time: str | None) -> None:
        now = self.clock()
        with self.lock:
            previous = self.current
            if previous is not None and version < previous:
                self.ring.clear()                      # recreated secret: start over
            for v, entry in self.ring.items():
                if entry["retire_at"] is None:
                    entry["retire_at"] = now + max(0.0, self.grace_s)
            self.ring[version] = {"value": value, "adopted_at": now, "retire_at": None}
            self.current = version
            self.expire(now)
            created = parse_time(created_time)
            self.adoptions.appendleft({
                "version": version, "previous": previous, "adopted_at": iso_ts(now),
                "vault_created_at": created_time,
                "vault_to_adopt_s": round(now - created.timestamp(), 2) if created else None,
                "previous_retires_at": iso_ts(now + self.grace_s) if previous is not None else None,
                "mode": self.mode,
            })
        if previous is None:
            self.log("INFO", f"key ring loaded: v{version} (mode {self.mode}, grace {int(self.grace_s)}s)")
        else:
            tail = "retired now" if self.grace_s <= 0 else f"still accepted for {int(self.grace_s)}s"
            self.log("WARN", f"ADOPTED v{version}; v{previous} {tail}")

    def expire(self, now: float) -> None:
        for v in [v for v, e in self.ring.items() if e["retire_at"] is not None and e["retire_at"] <= now]:
            del self.ring[v]
            for a in self.adoptions:
                if a["previous"] == v and "previous_retired_at" not in a:
                    a["previous_retired_at"] = iso_ts(now)
            self.log("INFO", f"v{v} retired: requests signed with it are now refused")

    # -- one request --------------------------------------------------------------
    def check(self, req: object) -> dict:
        now = self.clock()
        reason = protocol.check_shape(req)
        verdict, version = "DENIED", None
        client = req.get("client") if reason is None and isinstance(req, dict) else None
        if reason is None:
            assert isinstance(req, dict)
            version = req["key_version"]
            with self.lock:
                self.expire(now)
                entry = self.ring.get(version)
                current = self.current
            if abs(now - req["ts"]) > protocol.WINDOW_S:
                reason = "stale-timestamp"
            elif entry is None:
                reason = "version-unknown" if current is not None and version > current else "version-retired"
            elif not hmac.compare_digest(req["sig"], protocol.sign(entry["value"], req["client"], req["ts"], req["nonce"])):
                reason = "bad-signature"
            elif self.nonces.seen_before(req["nonce"], now):
                reason = "replayed-nonce"
            else:
                verdict = "GRANTED"
                reason = "current" if version == current else f"grace (v{current} is current)"
        with self.lock:
            self.verdicts[f"{verdict}:{reason.split(' ')[0]}"] += 1
            self.recent.appendleft({"at": iso_ts(now), "verdict": verdict, "reason": reason, "version": version,
                                    "client": client})
        if verdict == "DENIED":
            self.log("WARN", f"ACCESS DENIED v{version} client={client or '-'} reason={reason} (fictional door; real trust decision)")
        return {"verdict": verdict, "reason": reason, "key_version": version, "verifier_version": self.current}

    # -- loop and status ----------------------------------------------------------
    def poll_once(self) -> None:
        self.read_health()
        snap = self.read_snapshot()
        if snap is not None and snap.version != self.current:
            self.adopt(snap.version, snap.value, snap.created_time)
        with self.lock:
            self.expire(self.clock())

    def status(self) -> dict:
        state, reason = self.credential_state(self.current is not None)
        with self.lock:
            ring = [{"version": v, "adopted_at": iso_ts(e["adopted_at"]),
                     "retires_at": iso_ts(e["retire_at"]) if e["retire_at"] else None,
                     "current": v == self.current} for v, e in self.ring.items()]
            body = {"mode": self.mode, "grace_seconds": self.grace_s, "current_version": self.current,
                    "ring": ring, "adoptions": list(self.adoptions), "verdicts": dict(self.verdicts),
                    "recent": list(self.recent)[:20], "state": state, "reason": reason}
        return {**self.base_status(), "verifier": body}

    def enter_server(self) -> ThreadingHTTPServer:
        verifier = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):  # noqa: N802
                if self.path.split("?")[0] != "/enter":
                    return self._send(404, {"error": "not found"})
                try:
                    length = min(int(self.headers.get("Content-Length") or 0), 2048)
                    req = json.loads(self.rfile.read(length) or b"{}")
                except ValueError:
                    req = None
                result = verifier.check(req)
                self._send(200 if result["verdict"] == "GRANTED" else 403, result)

            def do_GET(self):  # noqa: N802
                self._send(200, {"ok": True}) if self.path == "/healthz" else self._send(404, {"error": "not found"})

            def _send(self, code, body):
                data = json.dumps(body).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *args):
                return

        return ThreadingHTTPServer(("0.0.0.0", self.enter_port), Handler)

    def run(self) -> None:
        self.log("INFO", f"Secure Door verifier starting: mode {self.mode}, grace {int(self.grace_s)}s, "
                         f"window {protocol.WINDOW_S}s (fictional door; real trust decision)")
        self.serve_status()
        enter = self.enter_server()
        threading.Thread(target=enter.serve_forever, daemon=True).start()
        while not self.stop.is_set():
            try:
                self.poll_once()
            except Exception as exc:
                self.log("ERROR", f"poll failed: {exc.__class__.__name__}")
            self.stop.wait(self.poll_s)


def iso_ts(epoch: float | None) -> str | None:
    if epoch is None:
        return None
    return iso(datetime.fromtimestamp(epoch, timezone.utc))


def main() -> None:
    v = Verifier()
    signal.signal(signal.SIGTERM, lambda *_: v.stop.set())
    v.run()

