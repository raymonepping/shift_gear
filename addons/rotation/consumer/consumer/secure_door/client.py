"""door-client — keeps running while its secret rotates underneath it.

It loads the shared secret from its *own* Vault Agent, hot-reloads a new KV
version without restarting, and asks the verifier to open the door every
DOOR_REQUEST_S with a signed request (protocol.py). It never calls Vault.

When the verifier has not adopted the newest version yet (`version-unknown`),
the client retries once with the previous version it still holds in memory —
a normal two-party cut-over, recorded as a fallback. When the verifier has
retired the version the client holds (`version-retired`), the client is denied
until its own Agent delivers the new one: that is the measured failure window.

Extra settings: DOOR_VERIFIER_URL (http://door-verifier.<ns>.svc:8080/enter),
DOOR_CLIENT_ID, DOOR_REQUEST_S (default 1), DOOR_STATE_FILE (last seen version).
"""
from __future__ import annotations

import json
import os
import signal
import tempfile
import time
import urllib.error
import urllib.request
from collections import Counter, deque
from datetime import datetime, timezone
from statistics import median

from . import protocol, snapshot
from .health import iso, parse_time, utcnow
from .party import Party


class Client(Party):
    role = "client"

    def __init__(self, env=None, out=None, send=None):
        super().__init__(env, **({"out": out} if out else {}))
        self.verifier_url = self.env.get("DOOR_VERIFIER_URL", "http://door-verifier:8080/enter")
        self.client_id = self.env.get("DOOR_CLIENT_ID", "door-client")
        self.request_s = float(self.env.get("DOOR_REQUEST_S", "1"))
        self.state_file = self.env.get("DOOR_STATE_FILE", "/state/last-version.json")
        self.send = send or self._http_send
        self.cached: snapshot.Snapshot | None = None
        self.previous: snapshot.Snapshot | None = None       # kept for a fallback until the verifier catches up
        self.loaded_at: datetime | None = None
        self.outcomes: Counter[str] = Counter()
        self.rotations: deque[dict] = deque(maxlen=50)
        self.windows: deque[dict] = deque(maxlen=50)         # denial windows
        self.open_window: dict | None = None
        self.last: dict | None = None
        self.vault_to_file: list[float] = []
        self.file_to_reload: list[float] = []
        self.next_request = 0.0
        self.previous_version = self._load_previous_version()

    # -- persistence of the last seen version (non-secret) -------------------------
    def _load_previous_version(self) -> int | None:
        try:
            with open(self.state_file, "rb") as handle:
                v = json.loads(handle.read(1024)).get("last_version")
            return v if isinstance(v, int) and v > 0 else None
        except (OSError, ValueError, AttributeError):
            return None

    def _save_version(self, version: int) -> None:
        try:
            fd, tmp = tempfile.mkstemp(dir=os.path.dirname(self.state_file) or ".", prefix=".tmp-")
            with os.fdopen(fd, "w") as handle:
                json.dump({"last_version": version, "at": iso(utcnow())}, handle)
            os.replace(tmp, self.state_file)
        except OSError:
            pass

    # -- hot reload ---------------------------------------------------------------
    def load(self, snap: snapshot.Snapshot) -> None:
        old = self.cached
        if old is None:
            prev = self.previous_version
            if prev is not None and prev != snap.version:
                missed = max(0, snap.version - prev - 1)
                self.log("WARN", f"ROTATION DETECTED v{prev} -> v{snap.version} while stopped; missed {missed} intermediate version(s)")
                self.rotations.appendleft({"from": prev, "to": snap.version, "missed": missed, "while_stopped": True,
                                           "vault_created_at": snap.created_time, "reloaded_at": iso(utcnow())})
        else:
            missed = max(0, snap.version - old.version - 1)
            note = f"; missed {missed} intermediate version(s)" if missed else ""
            self.log("WARN", f"ROTATION DETECTED v{old.version} -> v{snap.version}{note}")
        self.previous, self.cached = old, snap
        self.loaded_at = utcnow()
        self.previous_version = snap.version
        self._save_version(snap.version)
        self.log("INFO", f"credential {'reloaded' if old else 'loaded'} version=v{snap.version} fp={snap.fingerprint}")
        if old is not None:
            created = parse_time(snap.created_time)
            file_at = datetime.fromtimestamp(snap.mtime, timezone.utc) if snap.mtime else None
            v2f = (file_at - created).total_seconds() if created and file_at else None
            f2r = (self.loaded_at - file_at).total_seconds() if file_at else None
            if v2f is not None and v2f >= 0:
                self.vault_to_file.append(round(v2f, 3))
            if f2r is not None and f2r >= 0:
                self.file_to_reload.append(round(f2r, 3))
            self.rotations.appendleft({"from": old.version, "to": snap.version, "missed": missed,
                                       "vault_created_at": snap.created_time, "file_seen_at": iso(file_at),
                                       "reloaded_at": iso(self.loaded_at), "vault_to_file_s": v2f,
                                       "file_to_reload_s": f2r})

    # -- the door -------------------------------------------------------------------
    def _http_send(self, body: dict) -> dict:
        req = urllib.request.Request(self.verifier_url, data=json.dumps(body).encode(), method="POST",
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=3) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as exc:
            try:
                return json.load(exc)
            except ValueError:
                return {"verdict": "DENIED", "reason": f"http-{exc.code}"}
        except (urllib.error.URLError, TimeoutError, OSError):
            return {"verdict": "UNREACHABLE", "reason": "verifier unreachable"}

    def knock(self) -> dict:
        assert self.cached is not None
        answer = self.send(protocol.new_request(self.cached.value, self.cached.version, self.client_id))
        used = self.cached.version
        if answer.get("reason") == "version-unknown" and self.previous is not None:
            # The verifier has not adopted our newest version yet: prove the previous one instead.
            answer = self.send(protocol.new_request(self.previous.value, self.previous.version, self.client_id))
            used = self.previous.version
            self.outcomes["fallback"] += 1
            answer = {**answer, "fallback": True}
        elif answer.get("verdict") == "GRANTED" and self.previous is not None and used == self.cached.version:
            self.previous = None              # the verifier knows our newest version: drop the old one
        self.record(answer, used)
        return answer

    def record(self, answer: dict, version: int) -> None:
        verdict, reason = answer.get("verdict", "DENIED"), answer.get("reason", "")
        now = utcnow()
        self.outcomes[verdict] += 1
        self.last = {"at": iso(now), "verdict": verdict, "reason": reason, "version": version,
                     "verifier_version": answer.get("verifier_version"), "fallback": bool(answer.get("fallback"))}
        if verdict == "GRANTED":
            if self.open_window is not None:
                w = self.open_window
                w["end"] = iso(now)
                w["seconds"] = round((now - parse_time(w["start"])).total_seconds(), 2)
                self.windows.appendleft(w)
                self.open_window = None
                self.log("INFO", f"ACCESS GRANTED again v{version} after {w['denied']} denied request(s) in {w['seconds']}s")
        else:
            if self.open_window is None:
                self.open_window = {"start": iso(now), "reason": reason, "version": version, "denied": 0, "reasons": {}}
                self.log("WARN", f"ACCESS DENIED v{version} reason={reason} (verifier holds v{answer.get('verifier_version')})")
            self.open_window["denied"] += 1
            key = reason.split(" ")[0] or verdict.lower()
            self.open_window["reasons"][key] = self.open_window["reasons"].get(key, 0) + 1

    # -- loop and status ---------------------------------------------------------------
    def poll_once(self) -> None:
        self.read_health()
        snap = self.read_snapshot()
        if snap is not None and (self.cached is None or snap.version != self.cached.version):
            self.load(snap)
        now = time.monotonic()
        if self.cached is not None and now >= self.next_request:
            self.next_request = now + self.request_s
            self.knock()

    @staticmethod
    def _stats(samples: list[float]) -> dict:
        return {"p50": round(median(samples), 2), "max": round(max(samples), 2), "n": len(samples)} if samples \
            else {"p50": None, "max": None, "n": 0}

    def status(self) -> dict:
        state, reason = self.credential_state(self.cached is not None)
        with self.lock:
            body = {
                "version": self.cached.version if self.cached else None,
                "fingerprint": self.cached.fingerprint if self.cached else None,
                "holds_previous": self.previous.version if self.previous else None,
                "loaded_at": iso(self.loaded_at), "state": state, "reason": reason,
                "outcomes": dict(self.outcomes), "last": self.last,
                "open_window": self.open_window, "windows": list(self.windows),
                "rotations": list(self.rotations),
                "latency": {"vault_to_file_s": self._stats(self.vault_to_file),
                            "file_to_reload_s": self._stats(self.file_to_reload)},
                "poll_interval_s": self.poll_s, "request_interval_s": self.request_s,
            }
        return {**self.base_status(), "client": body}

    def run(self) -> None:
        self.log("INFO", f"Secure Door client starting: verifier {self.verifier_url}, request every {self.request_s}s "
                         f"(fictional door; real trust decision by a separate verifier)")
        if self.previous_version:
            self.log("INFO", f"last seen before this start: v{self.previous_version}")
        self.serve_status()
        while not self.stop.is_set():
            try:
                self.poll_once()
            except Exception as exc:
                self.log("ERROR", f"poll failed: {exc.__class__.__name__}")
            self.stop.wait(min(self.poll_s, self.request_s))


def main() -> None:
    c = Client()
    signal.signal(signal.SIGTERM, lambda *_: c.stop.set())
    c.run()
