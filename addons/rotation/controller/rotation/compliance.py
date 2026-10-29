"""Compliance of each managed secret against its type policy (pure).

Shared by the controller (/compliance) and the host CLI (`make
rotation-report`). The CLI computes it from Vault alone, so the report stays
honest while the controller is down: secrets simply become overdue.
"""
from __future__ import annotations

from datetime import datetime

from . import history as h
from .config import Config, Secret
from .vault import Metadata, iso


def evaluate(secret: Secret, config: Config, md: Metadata | None, now: datetime,
             reads_reported: bool = True) -> dict:
    result: dict = {
        "secret": secret.id,
        "path": f"{config.mount}/{secret.rel_path}",
        "type": secret.type.name,
        "owner": secret.owner,
        "strategies": list(secret.strategies),
        "compliant": False,
        "reasons": [],      # policy violations
        "warnings": [],     # missing data — reported, but not a violation
    }
    reasons: list[str] = result["reasons"]
    if md is None or md.current_version == 0:
        reasons.append("not onboarded: the secret does not exist in Vault yet")
        return result

    current = md.current_version
    created = md.created(current)
    records = h.decode(md.custom)
    age = (now - created).total_seconds() if created else None
    reads_raw = md.custom.get(h.READS_SINCE)
    reads = int(reads_raw) if (reads_raw or "").isdigit() and reads_reported else None
    retained = sum(1 for v, info in md.versions.items() if not info.get("destroyed"))
    expected_retained = min(config.max_versions, current)

    result.update({
        "version": current,
        "fingerprint": records[current].fingerprint if current in records else None,
        "last_rotated": iso(created) if created else None,
        "last_trigger": md.custom.get(h.LAST_TRIGGER),
        "age_seconds": int(age) if age is not None else None,
        "max_age_seconds": secret.type.max_age,
        "reads_since": reads,
        "max_reads": secret.max_reads if "usage" in secret.strategies else None,
        "versions_retained": retained,
        "max_versions": config.max_versions,
    })

    if age is None:
        reasons.append("age unknown: Vault reports no created_time for the current version")
    elif age > secret.type.max_age:
        reasons.append(f"overdue: age {int(age)}s > max_age {secret.type.max_age}s")
    if "usage" in secret.strategies and secret.max_reads is not None:
        if reads is None:
            result["warnings"].append("usage not reported (audit collector unavailable)")
        elif reads > secret.max_reads:
            reasons.append(f"over-used: {reads} reads > max_reads {secret.max_reads}")
    if md.max_versions != config.max_versions:
        reasons.append(f"history retention {md.max_versions} != policy {config.max_versions}")
    if not md.cas_required:
        reasons.append("cas_required is off")
    if md.custom.get(h.OWNER) != secret.owner:
        reasons.append(f"owner in Vault ({md.custom.get(h.OWNER) or 'none'}) != declared owner {secret.owner}")
    if md.custom.get(h.MANAGED_BY) != h.MANAGED_BY_VALUE:
        reasons.append("not marked as managed by the rotation controller")
    if current not in records:
        reasons.append(f"version {current} has no rotation record (written outside the controller?)")
    elif records[current].trigger not in h.TRIGGERS:
        reasons.append(f"version {current} has an unknown trigger '{records[current].trigger}'")
    if retained < expected_retained:
        reasons.append(f"only {retained} of {expected_retained} expected versions retained")

    result["compliant"] = not reasons
    return result


def summary(results: list[dict], now: datetime, controller: str) -> dict:
    total = len(results)
    compliant = sum(1 for r in results if r["compliant"])
    overdue = [r for r in results if any(x.startswith("overdue") for x in r["reasons"])]
    oldest = max(overdue, key=lambda r: r.get("age_seconds") or 0, default=None)
    return {
        "generated_at": iso(now),
        "controller": controller,
        "total": total,
        "compliant": compliant,
        "non_compliant": total - compliant,
        "compliance_percent": round(100.0 * compliant / total, 1) if total else 100.0,
        "oldest_overdue": oldest["secret"] if oldest else None,
        "by_type": _by_type(results),
    }


def _by_type(results: list[dict]) -> dict:
    out: dict[str, dict[str, int]] = {}
    for r in results:
        bucket = out.setdefault(r["type"], {"total": 0, "compliant": 0})
        bucket["total"] += 1
        bucket["compliant"] += int(r["compliant"])
    return out
