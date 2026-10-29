"""Load and validate the declarative rotation configuration.

The runtime reads JSON (Terraform renders rotation.yaml with
jsonencode(yamldecode(...))). The host CLI may also read the YAML file when
PyYAML is importable (Ansible's interpreter has it).
"""
from __future__ import annotations

import fnmatch
import json
import re
from dataclasses import dataclass, field
from pathlib import Path

STRATEGIES = ("time", "usage", "event")
# Who owns the credential decides whether KV rotation means anything (prompt 01_10).
OWNERS = {
    "application": None,   # the only owner this add-on accepts
    "vault-native": "use the matching Vault engine instead (database, PKI or Transit rotate natively)",
    "external-provider": ("rotating only the KV copy breaks authentication; the provider must issue the "
                          "new credential, which this add-on does not do"),
}
GENERATOR_KINDS = ("chars", "bytes", "password")
CHARSETS = ("alnum", "alpha", "hex", "lower")
ENCODINGS = ("base64url", "hex")
PASSWORD_CLASSES = ("lower", "upper", "digit", "symbol")
# custom_metadata allows 64 keys of <= 512 bytes; leave room for the summary keys.
MAX_VERSIONS_LIMIT = 50
SUMMARY_KEYS = 12            # history.py: managed_by … retired_at (asserted in the tests)
MAX_EVENT_RULES = 8
MAX_WATCH_BYTES = 480        # encoded rotation_watch must stay under Vault's 512-byte value limit

_DNS_LABEL = re.compile(r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$")
_DURATION = re.compile(r"^(\d+)([smhd])$")
_UNIT = {"s": 1, "m": 60, "h": 3600, "d": 86400}


class ConfigError(ValueError):
    """The configuration violates a rule; the message names the rule."""


def parse_duration(value: str | int, where: str) -> int:
    """'60s', '5m', '2h', '30d' -> seconds. Integers are seconds."""
    if isinstance(value, int) and value > 0:
        return value
    match = _DURATION.match(str(value).strip())
    if not match or int(match.group(1)) <= 0:
        raise ConfigError(f"{where}: '{value}' is not a duration like 60s, 5m, 2h or 30d")
    return int(match.group(1)) * _UNIT[match.group(2)]


@dataclass(frozen=True)
class Generator:
    kind: str
    length: int = 0          # chars / password
    charset: str = "alnum"   # chars
    nbytes: int = 0          # bytes
    encoding: str = "base64url"
    classes: tuple[str, ...] = ()

    def output_length(self) -> int:
        if self.kind == "bytes":
            if self.encoding == "hex":
                return self.nbytes * 2
            return (4 * self.nbytes + 2) // 3  # base64url without padding
        return self.length


@dataclass(frozen=True)
class SecretType:
    name: str
    generator: Generator
    interval: int
    max_age: int
    min_length: int
    max_reads: int | None


@dataclass(frozen=True)
class EventRule:
    match: str  # event type glob, e.g. kv-v2/data-* ("on" is a YAML 1.1 boolean, so not used)
    path: str   # mount-relative path, e.g. shift-gear/config/app-config

    def matches(self, event_type: str, rel_path: str) -> bool:
        return fnmatch.fnmatchcase(event_type, self.match) and rel_path == self.path


@dataclass(frozen=True)
class Secret:
    name: str
    type: SecretType
    strategies: tuple[str, ...]
    interval: int
    max_reads: int | None
    events: tuple[EventRule, ...]
    rel_path: str           # <prefix>/<type>/<name>
    owner: str = "application"

    @property
    def id(self) -> str:
        return f"{self.type.name}/{self.name}"


@dataclass(frozen=True)
class Config:
    mount: str
    prefix: str
    loop_seconds: int
    max_versions: int
    types: dict[str, SecretType]
    secrets: tuple[Secret, ...] = field(default_factory=tuple)

    def secret(self, secret_id: str) -> Secret:
        for item in self.secrets:
            if item.id == secret_id:
                return item
        known = ", ".join(s.id for s in self.secrets)
        raise ConfigError(f"unknown secret '{secret_id}' (known: {known})")

    def by_rel_path(self, rel_path: str) -> Secret | None:
        for item in self.secrets:
            if item.rel_path == rel_path:
                return item
        return None


def _require(mapping: dict, key: str, where: str):
    if not isinstance(mapping, dict) or key not in mapping:
        raise ConfigError(f"{where}: missing '{key}'")
    return mapping[key]


def _generator(raw: dict, where: str) -> Generator:
    kind = _require(raw, "kind", where)
    if kind not in GENERATOR_KINDS:
        raise ConfigError(f"{where}.kind: '{kind}' not one of {GENERATOR_KINDS}")
    if kind == "chars":
        charset = raw.get("charset", "alnum")
        if charset not in CHARSETS:
            raise ConfigError(f"{where}.charset: '{charset}' not one of {CHARSETS}")
        length = int(_require(raw, "length", where))
        if length < 16:
            raise ConfigError(f"{where}.length: {length} < 16 (entropy floor)")
        return Generator(kind=kind, length=length, charset=charset)
    if kind == "bytes":
        nbytes = int(_require(raw, "bytes", where))
        encoding = raw.get("encoding", "base64url")
        if nbytes < 16:
            raise ConfigError(f"{where}.bytes: {nbytes} < 16 (entropy floor)")
        if encoding not in ENCODINGS:
            raise ConfigError(f"{where}.encoding: '{encoding}' not one of {ENCODINGS}")
        return Generator(kind=kind, nbytes=nbytes, encoding=encoding)
    length = int(_require(raw, "length", where))
    classes = tuple(raw.get("classes", PASSWORD_CLASSES))
    unknown = [c for c in classes if c not in PASSWORD_CLASSES]
    if unknown or not classes:
        raise ConfigError(f"{where}.classes: {list(classes)} must be a non-empty subset of {PASSWORD_CLASSES}")
    if length < max(16, len(classes)):
        raise ConfigError(f"{where}.length: {length} too short (>= 16 and >= number of classes)")
    return Generator(kind=kind, length=length, classes=classes)


def _type(name: str, raw: dict) -> SecretType:
    where = f"types.{name}"
    if not _DNS_LABEL.match(name):
        raise ConfigError(f"{where}: type name must be a DNS label")
    generator = _generator(_require(raw, "generator", where), f"{where}.generator")
    schedule = _require(raw, "schedule", where)
    policy = _require(raw, "policy", where)
    interval = parse_duration(_require(schedule, "interval", f"{where}.schedule"), f"{where}.schedule.interval")
    max_age = parse_duration(_require(policy, "max_age", f"{where}.policy"), f"{where}.policy.max_age")
    min_length = int(_require(policy, "min_length", f"{where}.policy"))
    max_reads = policy.get("max_reads")
    if interval > max_age:
        raise ConfigError(f"{where}: schedule.interval ({interval}s) exceeds policy.max_age ({max_age}s)")
    if generator.output_length() < min_length:
        raise ConfigError(
            f"{where}: generator output length {generator.output_length()} is below policy.min_length {min_length}")
    if max_reads is not None and int(max_reads) < 1:
        raise ConfigError(f"{where}.policy.max_reads must be >= 1")
    return SecretType(name=name, generator=generator, interval=interval, max_age=max_age,
                      min_length=min_length, max_reads=int(max_reads) if max_reads is not None else None)


def _secret(raw: dict, types: dict[str, SecretType], prefix: str, index: int) -> Secret:
    where = f"secrets[{index}]"
    name = _require(raw, "name", where)
    if not _DNS_LABEL.match(str(name)):
        raise ConfigError(f"{where}.name: '{name}' must be a DNS label")
    type_name = _require(raw, "type", where)
    if type_name not in types:
        raise ConfigError(f"{where}.type: unknown type '{type_name}'")
    stype = types[type_name]
    owner = raw.get("owner")
    if owner is None:
        raise ConfigError(f"{where}.owner: missing — declare who owns the credential: "
                          f"application, vault-native or external-provider (only application is managed here)")
    if owner not in OWNERS:
        raise ConfigError(f"{where}.owner: '{owner}' is not one of {sorted(OWNERS)}")
    if OWNERS[owner] is not None:
        raise ConfigError(f"{where}.owner: {owner} — {OWNERS[owner]}")
    strategies = tuple(raw.get("strategies", ["time"]))
    bad = [s for s in strategies if s not in STRATEGIES]
    if bad or not strategies:
        raise ConfigError(f"{where}.strategies: {list(strategies)} must be a non-empty subset of {STRATEGIES}")

    if "time" not in strategies:
        # Every type has a max_age, so every secret needs a schedule that keeps
        # it inside that age. Usage and events can only rotate *earlier*.
        raise ConfigError(f"{where}.strategies: must include 'time' (type '{type_name}' has max_age "
                          f"{stype.max_age}s; usage and event only rotate earlier)")

    interval = stype.interval
    if "interval" in raw:
        interval = parse_duration(raw["interval"], f"{where}.interval")
        if interval > stype.max_age:
            raise ConfigError(f"{where}.interval ({interval}s) loosens type policy max_age ({stype.max_age}s)")

    max_reads = stype.max_reads
    usage = raw.get("usage") or {}
    if "max_reads" in usage:
        max_reads = int(usage["max_reads"])
        if max_reads < 1:
            raise ConfigError(f"{where}.usage.max_reads must be >= 1")
        if stype.max_reads is not None and max_reads > stype.max_reads:
            raise ConfigError(f"{where}.usage.max_reads ({max_reads}) loosens type policy max_reads ({stype.max_reads})")
    if "usage" in strategies and max_reads is None:
        raise ConfigError(f"{where}: strategy 'usage' needs usage.max_reads or a type policy max_reads")

    rel_path = f"{prefix}/{type_name}/{name}"
    events = []
    for j, rule in enumerate(raw.get("events") or []):
        match = _require(rule, "match", f"{where}.events[{j}]")
        path = str(_require(rule, "path", f"{where}.events[{j}]")).strip("/")
        if not str(match).startswith("kv-v2/"):
            raise ConfigError(f"{where}.events[{j}].match: only kv-v2/* event types are supported")
        if path == prefix or path.startswith(prefix + "/"):
            raise ConfigError(f"{where}.events[{j}].path: '{path}' is under the managed prefix (rotation loop)")
        events.append(EventRule(match=str(match), path=path))
    if len(events) > MAX_EVENT_RULES:
        raise ConfigError(f"{where}.events: at most {MAX_EVENT_RULES} rules per secret")
    watch_bytes = len(",".join(f"{e.path}@{10**9}" for e in events).encode())
    if watch_bytes > MAX_WATCH_BYTES:
        raise ConfigError(f"{where}.events: the version checkpoint would be {watch_bytes} bytes "
                          f"(limit {MAX_WATCH_BYTES}; custom metadata values hold 512)")
    if events and "event" not in strategies:
        raise ConfigError(f"{where}: events are declared but strategy 'event' is not enabled")

    return Secret(name=str(name), type=stype, strategies=strategies, interval=interval,
                  max_reads=max_reads, events=tuple(events), rel_path=rel_path, owner=str(owner))


def parse(document: dict) -> Config:
    root = _require(document, "rotation", "document")
    mount = str(root.get("mount", "kv")).strip("/")
    prefix = str(_require(root, "prefix", "rotation")).strip("/")
    loop_seconds = int(root.get("loop_seconds", 10))
    if not 2 <= loop_seconds <= 300:
        raise ConfigError("rotation.loop_seconds must be between 2 and 300")
    max_versions = int((root.get("defaults") or {}).get("max_versions", 20))
    if not 2 <= max_versions <= MAX_VERSIONS_LIMIT:
        raise ConfigError(f"rotation.defaults.max_versions must be between 2 and {MAX_VERSIONS_LIMIT}")
    raw_types = _require(root, "types", "rotation")
    if not raw_types:
        raise ConfigError("rotation.types: at least one type is required")
    types = {name: _type(name, raw) for name, raw in raw_types.items()}
    secrets = tuple(_secret(raw, types, prefix, i) for i, raw in enumerate(root.get("secrets") or []))
    seen: set[str] = set()
    for item in secrets:
        if item.rel_path in seen:
            raise ConfigError(f"secrets: duplicate secret '{item.id}'")
        seen.add(item.rel_path)
        if item.interval <= loop_seconds:
            raise ConfigError(f"secrets '{item.id}': interval must be longer than loop_seconds")
    return Config(mount=mount, prefix=prefix, loop_seconds=loop_seconds,
                  max_versions=max_versions, types=types, secrets=secrets)


def load(path: str | Path) -> Config:
    path = Path(path)
    text = path.read_text()
    if path.suffix in (".yaml", ".yml"):
        try:
            import yaml  # type: ignore[import-not-found]  # host CLI only
        except ImportError as exc:  # pragma: no cover - environment dependent
            raise ConfigError("reading YAML needs PyYAML; the runtime reads the rendered JSON") from exc
        return parse(yaml.safe_load(text))
    return parse(json.loads(text))


def describe(config: Config) -> dict:
    """Non-secret, JSON-able view of the configuration (for /status and the UI)."""
    return {
        "mount": config.mount,
        "prefix": config.prefix,
        "loop_seconds": config.loop_seconds,
        "max_versions": config.max_versions,
        "types": {
            name: {
                "generator": {k: v for k, v in vars(t.generator).items() if v not in (0, (), "")},
                "interval_seconds": t.interval,
                "max_age_seconds": t.max_age,
                "min_length": t.min_length,
                "max_reads": t.max_reads,
            } for name, t in config.types.items()
        },
        "secrets": [
            {
                "id": s.id,
                "path": f"{config.mount}/{s.rel_path}",
                "type": s.type.name,
                "owner": s.owner,
                "strategies": list(s.strategies),
                "interval_seconds": s.interval,
                "max_reads": s.max_reads,
                "events": [{"match": e.match, "path": e.path} for e in s.events],
            } for s in config.secrets
        ],
    }
