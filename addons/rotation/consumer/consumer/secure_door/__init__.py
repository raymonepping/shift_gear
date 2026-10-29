"""Secure Door — a read-only KV v2 rotation consumer (prompt 01_09).

The Vault Agent sidecar alone talks to Vault and renders an atomic JSON
snapshot of the watched secret into a memory-backed volume. This package reads
that file, hot-reloads the credential when the KV version changes, and runs a
*fictional* Secure Door that shows a stale cached credential being denied and
the reloaded one being granted. It never calls Vault and never sees a token.
"""

__version__ = "0.1.0"
