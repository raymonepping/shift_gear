"""KV v2 value rotation controller (standard library only).

Rotates values *inside* Vault KV v2: each rotation is a new version written
with check-and-set. Vault is the only store; the controller keeps no state
of its own. See addons/rotation/README.md and docs/rotation.md.
"""

__version__ = "0.1.0"
