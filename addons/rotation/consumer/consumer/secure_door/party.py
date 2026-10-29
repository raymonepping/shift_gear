"""What the verifier and the client have in common.

Each party runs in its own pod with its own Vault Agent and identity. Both read
only their own Agent's snapshot; neither holds a token or calls Vault. Both
publish a non-secret status document over HTTP for the board.

Settings (DOOR_*; never VAULT_*):
  DOOR_SECRET             display id, e.g. api-key/secure-door
  DOOR_SNAPSHOT_FILE      this party's Agent-rendered JSON (read-only here)
  DOOR_PROBE_FILE         this party's vault-probe result
  DOOR_AGENT_LOG          this party's Agent log (refresh / fetch-error evidence)
  DOOR_STATUS_PORT        status endpoint for the board (default 9090)
  DOOR_POLL_S             local snapshot poll (default 1)
  DOOR_STALE_AFTER_S      unreachable this long -> stale (default 60)
  DOOR_RENDER_INTERVAL_S  the Agent's configured interval (display only)
  DOOR_LOG_LEVEL          INFO | DEBUG
"""
from __future__ import annotations

import json
import os
import sys
import threading
from collections import deque
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import __version__, health, snapshot
from .health import iso, utcnow

LEVELS = {"DEBUG": 10, "INFO": 20, "WARN": 30, "ERROR": 40}


class Party:
    role = "party"

    def __init__(self, env: dict[str, str] | None = None, out=sys.stdout):
        e = env if env is not None else dict(os.environ)
        self.env = e
        self.secret = e.get("DOOR_SECRET", "api-key/secure-door")
        self.snapshot_file = e.get("DOOR_SNAPSHOT_FILE", "/vault/render/secret.json")
        self.probe_file = e.get("DOOR_PROBE_FILE", "/health/vault.json")
        self.agent_log = e.get("DOOR_AGENT_LOG", "/agent-log/agent.log")
        self.status_port = int(e.get("DOOR_STATUS_PORT", "9090"))
        self.poll_s = float(e.get("DOOR_POLL_S", "1"))
        self.stale_after_s = float(e.get("DOOR_STALE_AFTER_S", "60"))
        self.render_interval_s = float(e.get("DOOR_RENDER_INTERVAL_S", "5"))
        self.level = LEVELS.get(e.get("DOOR_LOG_LEVEL", "INFO").upper(), 20)
        self.out = out
        self.started_at = utcnow()
        self.lock = threading.RLock()
        self.stop = threading.Event()
        self.log_ring: deque[dict] = deque(maxlen=200)
        self.probe = health.VaultProbe()
        self.agent = health.AgentEvidence()
        self.snapshot_problem: str | None = None
        self.last_change_rendered: datetime | None = None

    # -- logging (never a value) ------------------------------------------------
    def log(self, level: str, msg: str) -> None:
        at = utcnow()
        with self.lock:
            self.log_ring.append({"at": iso(at), "level": level, "source": self.role, "msg": msg})
        if LEVELS[level] >= self.level:
            print(f"{iso(at)} {level:<5} [{self.role}] {msg}", file=self.out, flush=True)

    # -- this party's own Agent snapshot and health -----------------------------
    def read_health(self) -> None:
        self.probe = health.read_probe(self.probe_file, self.probe, max(15.0, 3 * self.render_interval_s))
        self.agent = health.scan_agent_log(self.agent_log, self.agent)

    def read_snapshot(self) -> snapshot.Snapshot | None:
        try:
            snap = snapshot.read(self.snapshot_file)
            self.snapshot_problem = None
            self.last_change_rendered = datetime.fromtimestamp(snap.mtime, timezone.utc) if snap.mtime else None
            return snap
        except snapshot.SnapshotMissing:
            self.snapshot_problem = "no rendered snapshot yet"
        except snapshot.SnapshotInvalid as exc:
            if self.snapshot_problem != str(exc):
                self.log("ERROR", f"rendered snapshot rejected: {exc} (keeping last-known-good)")
            self.snapshot_problem = str(exc)
        return None

    def credential_state(self, loaded: bool) -> tuple[str, str]:
        if not loaded:
            bad = self.snapshot_problem and self.snapshot_problem != "no rendered snapshot yet"
            return ("error", self.snapshot_problem or "") if bad else ("no-data", self.snapshot_problem or "no rendered snapshot yet")
        if self.agent.last_error_at and (self.agent.last_refresh is None or self.agent.last_error_at > self.agent.last_refresh):
            return "stale", self.agent.last_error or "Agent reported a fetch error"
        if self.probe.state == "reachable":
            return "current", "loaded; Vault reachable"
        down_for = (utcnow() - self.probe.since).total_seconds() if self.probe.since else 0
        if self.probe.state in ("unreachable", "sealed") and down_for > self.stale_after_s:
            return "stale", f"Vault {self.probe.state} for {int(down_for)}s"
        if self.probe.state == "unknown":
            return "last-known-good", "Vault connectivity unknown"
        return "last-known-good", f"Vault {self.probe.state} since {iso(self.probe.since)}"

    def health_status(self) -> dict:
        return {
            "agent": {
                "render_interval_s": self.render_interval_s,
                "last_change_rendered_at": iso(self.last_change_rendered),
                "last_refresh": {"observable": self.agent.observable, "at": iso(self.agent.last_refresh),
                                 "source": "agent log (template fetch success)" if self.agent.observable else None},
                "last_fetch_error": {"at": iso(self.agent.last_error_at), "what": self.agent.last_error}
                if self.agent.last_error_at else None,
            },
            "vault": {"probe": self.probe.state, "at": iso(self.probe.at), "since": iso(self.probe.since),
                      "detail": self.probe.detail, "meaning": "reachability only (unauthenticated status)"},
        }

    def status(self) -> dict:
        raise NotImplementedError

    def base_status(self) -> dict:
        with self.lock:
            log = list(self.log_ring)
        return {"schema": 2, "role": self.role, "secret": self.secret, "generated_at": iso(utcnow()),
                "pid": os.getpid(), "started_at": iso(self.started_at), "impl": __version__,
                **self.health_status(), "log": log}

    # -- HTTP ---------------------------------------------------------------------
    def status_server(self) -> ThreadingHTTPServer:
        party = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):  # noqa: N802
                path = self.path.split("?")[0]
                if path == "/healthz":
                    self._send(200, {"ok": True})
                elif path == "/status":
                    self._send(200, party.status())
                else:
                    self._send(404, {"error": "not found"})

            def _send(self, code, body):
                data = json.dumps(body).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *args):
                return

        return ThreadingHTTPServer(("0.0.0.0", self.status_port), Handler)

    def serve_status(self) -> ThreadingHTTPServer:
        server = self.status_server()
        threading.Thread(target=server.serve_forever, daemon=True).start()
        return server
