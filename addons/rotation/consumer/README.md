# Secure Door — a KV v2 rotation consumer (+ board)

The rotation add-on changes KV v2 values inside Vault. This shows the other
side: an application that **keeps running while its secret rotates
underneath it**. It notices each new version, reloads it without restarting,
and shows the old value being refused and the new one accepted. A small board
in the console's design (Vault daylight glass) makes all of that visible.

```text
make rotation-consumer-up       # install and prove (prints the board URL)
make rotation-consumer-logs     # follow the console: ROTATION DETECTED v54 -> v55 …
make rotation-rotate SECRET=api-key/secure-door   # rotate now, watch it arrive
make rotation-consumer-status   # credential · refresh · connectivity · door · latency
make rotation-consumer-test     # live proof c01–c07 + leak check
make rotation-consumer-down     # remove the consumer only
```

Board: `https://secure-door.<apps_domain>`.

## The honesty statement

**The Secure Door is fictional.**
- **GRANTED** means the app's cached credential matches Vault's latest
  version, as last rendered by the Agent.
- **DENIED** means it does not.
- No external service issued, validated or revoked anything.

What is real: the KV v2 versions, the Agent's reads, and the app's hot
reload. The board shows this statement in its hero, and every log line and
the status document repeat it.

## Architecture

```text
 rotation controller ──CAS write──► Vault kv/shift-gear/rotation/api-key/secure-door (v54, v55 …)
                                        ▲ read (policy sg-rotation-consumer: this one path)
 ┌ pod secure-door (ns sg-rotation-consumer) ───────────────────────────────────────────┐
 │ vault-agent   Kubernetes auth (projected token, mounted here only), no sink,         │
 │               no listener; template → /vault/render/secret.json (memory, atomic)     │
 │ vault-probe   unauthenticated `vault status` every 5 s → /health/vault.json          │
 │ consumer      reads the snapshot every 1 s, hot-reloads, runs the fictional door,    │
 │               writes non-secret /status/state.json                                   │
 │ board         Node, dependency-free: serves the page + /api/state + SSE from /status │
 └──────────────────────────────────────────────────── Route secure-door.<apps_domain> ─┘
```

- **Only the Agent talks to Vault.** The consumer holds no token, has no
  `VAULT_*` setting, and makes no HTTP call. `restricted-v2` runs all four
  containers as the same UID, so the isolation comes from the *mounts*: the
  token only in `vault-agent`, the rendered secret read-only in `consumer`,
  and `/status` read-only in `board`.
- **Limitation, recorded:** NetworkPolicies are pod-scoped, so the consumer
  container could open a TCP connection to Vault. Without a token it cannot
  do anything with it.
- **A dedicated secret.** `api-key/secure-door` has strategies `[time, event]`,
  every 60 s. It is not `api-key/demo`: that secret rotates after 3 reads,
  and an Agent re-reading it every few seconds would trigger a rotation
  storm. Usage-based rotation counts every audited reader, which is worth
  knowing for real deployments too.
- **Last seen version.** A small PVC (consumer only) keeps the last seen
  version number, so a restart can report `v54 -> v58; missed 3`.

## Health: three signals, never one "healthy" light

| Signal | Evidence | Without evidence |
| --- | --- | --- |
| Credential loaded | the consumer parsed a complete snapshot (version, time) | "no credential yet" |
| Last successful Vault refresh | the Agent's own log (TRACE `successful data response`, one per fetch) | "not observable — last change rendered …" |
| Vault connectivity | `vault-probe` (unauthenticated status: reachability, not authorisation) | "unknown" |

The credential state follows from evidence:
- `current`: loaded, and Vault reachable;
- `last-known-good`: Vault unreachable or sealed, or connectivity unknown;
- `stale`: an Agent fetch error, or unreachable for longer than 60 s;
- `no-data`;
- `error`.

The Agent rewrites the file only when the secret changes, so an unchanged
file is never a reason to call anything stale.

## Intervals: configured vs measured

| Stage | Configured | Measured |
| --- | --- | --- |
| Rotation (`api-key/secure-door`) | 60 s, plus `make rotation-rotate` | Vault `created_time` |
| Vault created → Agent wrote file | `static_secret_render_interval = "5s"` | see `make rotation-consumer-status` and `.build/addons/rotation/consumer-test.json` |
| File → consumer reloaded | poll 1 s | same |
| Reloaded → shown on the board | Server-Sent Events on each change (poll fallback 2 s) | c07 annotation |

Only measured numbers are written anywhere. The board shows median and max
with their sample count.

## Files

`consumer/secure_door/` (Python stdlib) · `board/` (`server.mjs`, `static/`, where
`tokens.css` is generated from the console's `main.css` by
`scripts/sync-board-css.py`) · `terraform/` (its own root and state) · `ansible/`
(the Agent's Kubernetes auth role, proof, removal) · `tests/` (offline unit,
board server, live suite, Playwright + axe).
