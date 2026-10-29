"""Fingerprints and log redaction.

A fingerprint is the first 12 hex characters of SHA-256 over a value. The
values this controller generates carry >= 128 bits of entropy (config.py
refuses less), so a 48-bit prefix identifies a version without revealing
anything usable about the value.
"""
from __future__ import annotations

import hashlib
import json
import logging
import sys
import threading
import time


def fingerprint(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()[:12]


class _Registry:
    """Values currently in memory; any log record containing one is redacted."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._values: dict[str, float] = {}

    def add(self, value: str, ttl: float = 600.0) -> None:
        if value:
            with self._lock:
                self._values[value] = time.monotonic() + ttl

    def scrub(self, text: str) -> str:
        now = time.monotonic()
        with self._lock:
            for value, expires in list(self._values.items()):
                if expires < now:
                    del self._values[value]
                elif value in text:
                    text = text.replace(value, "<redacted>")
        return text


REGISTRY = _Registry()


class RedactingFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        message = REGISTRY.scrub(record.getMessage())
        record.msg, record.args = message, None
        extra = getattr(record, "fields", None)
        if isinstance(extra, dict):
            record.fields = json.loads(REGISTRY.scrub(json.dumps(extra, default=str)))
        return True


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        body = {
            "time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(record.created)),
            "level": record.levelname.lower(),
            "msg": record.getMessage(),
        }
        extra = getattr(record, "fields", None)
        if isinstance(extra, dict):
            body.update(extra)
        if record.exc_info:
            body["error"] = REGISTRY.scrub(self.formatException(record.exc_info))
        return json.dumps(body, default=str)


def configure_logging(stream=sys.stdout, level: int = logging.INFO) -> logging.Logger:
    logger = logging.getLogger("rotation")
    logger.handlers.clear()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(JsonFormatter())
    handler.addFilter(RedactingFilter())
    logger.addHandler(handler)
    logger.setLevel(level)
    logger.propagate = False
    return logger


def log(logger: logging.Logger, msg: str, level: int = logging.INFO, **fields) -> None:
    logger.log(level, msg, extra={"fields": fields})
