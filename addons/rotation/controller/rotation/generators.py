"""Cryptographically secure value generation and the value policy check."""
from __future__ import annotations

import base64
import secrets
import string

from .config import Generator, SecretType

_ALPHABETS = {
    "alnum": string.ascii_letters + string.digits,
    "alpha": string.ascii_letters,
    "hex": "0123456789abcdef",
    "lower": string.ascii_lowercase + string.digits,
}
_CLASSES = {
    "lower": string.ascii_lowercase,
    "upper": string.ascii_uppercase,
    "digit": string.digits,
    # Symbols that survive shells, URLs and YAML without quoting surprises.
    "symbol": "-_.~!@#%^*+=",
}


def alphabet(generator: Generator) -> str:
    """Every character the generator may emit (used by the policy check and the EGP)."""
    if generator.kind == "chars":
        return _ALPHABETS[generator.charset]
    if generator.kind == "bytes":
        if generator.encoding == "hex":
            return _ALPHABETS["hex"]
        return string.ascii_letters + string.digits + "-_"
    return "".join(_CLASSES[c] for c in generator.classes)


def generate(generator: Generator) -> str:
    if generator.kind == "chars":
        chars = _ALPHABETS[generator.charset]
        return "".join(secrets.choice(chars) for _ in range(generator.length))
    if generator.kind == "bytes":
        raw = secrets.token_bytes(generator.nbytes)
        if generator.encoding == "hex":
            return raw.hex()
        return base64.urlsafe_b64encode(raw).decode().rstrip("=")
    # password: at least one of every class, then shuffle with a CSPRNG
    pools = [_CLASSES[c] for c in generator.classes]
    every = "".join(pools)
    chars = [secrets.choice(pool) for pool in pools]
    chars += [secrets.choice(every) for _ in range(generator.length - len(chars))]
    for i in range(len(chars) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        chars[i], chars[j] = chars[j], chars[i]
    return "".join(chars)


def policy_violations(value: str, stype: SecretType) -> list[str]:
    """Reasons a value breaks its type policy (empty list = compliant). Never echoes the value."""
    reasons = []
    if len(value) < stype.min_length:
        reasons.append(f"length {len(value)} < min_length {stype.min_length}")
    allowed = set(alphabet(stype.generator))
    if any(ch not in allowed for ch in value):
        reasons.append("contains characters outside the type's charset")
    if stype.generator.kind == "password":
        for name in stype.generator.classes:
            if not any(ch in _CLASSES[name] for ch in value):
                reasons.append(f"missing character class '{name}'")
    return reasons
