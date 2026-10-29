# Scenario 10 — KV v2 value rotation

**Question:** does the KV rotation add-on ([ADR D17](../../docs/decisions.md)) rotate a
KV v2 secret on its schedule, so that `api-key/demo` goes from X to Y to Z inside
Vault, each step a new version with a history record?

**Run:** `./scenarios/10_kv_rotation/run.sh` (optional `SECRET=<type>/<name>`,
`ROTATIONS=<n>`). It takes about one minute per rotation of `api-key/demo`.

**Expect:** `PASS: api-key/demo rotated vN -> vN+2 inside Vault`, preceded by the
history table (fingerprints, triggers, actors). Values are never printed.

**Skips** with `SKIP: the KV rotation add-on is not installed` when
`sg-rotation` does not exist. Install it with `make rotation-up`.

**Changes:** nothing. The controller rotates on its own schedule; the scenario only
watches. The full proof of every strategy is `make rotation-test`.
