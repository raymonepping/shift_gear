# Secure Door — application-owned rotation, two parties (+ board)

> Policy-driven rotation and distribution of application-owned static secrets
> using HashiCorp Vault KV v2 and Vault Agent.

The rotation add-on changes KV v2 values inside Vault. On its own that changes
nothing outside Vault. The Secure Door shows the case where it does: a secret
the application owns, checked by a verifier the application runs. When the
verifier adopts the new version and refuses the old one, trust has changed.
A small board in the console's design (Vault daylight glass) shows both sides.

```text
make rotation-consumer-up               # grace mode, 30 s (prints the board URL)
make rotation-consumer-up GRACE=0       # strict mode
make rotation-rotate SECRET=api-key/secure-door   # rotate now, watch both parties follow
make rotation-consumer-status           # both parties: versions, key ring, verdicts, windows, latency
make rotation-consumer-logs P=verifier  # or P=client / P=board, C=agent / C=probe
make rotation-consumer-test             # live proof d01–d08 + leak check
make rotation-consumer-down             # remove the Secure Door only
```

Board: `https://secure-door.<apps_domain>`.

## The honesty statement

**The door is fictional; the trust decision is real:** a separate verifier,
with its own identity and its own copy of the secret, accepts the new key and
rejects the old one.

Nothing is behind the door. The check in front of it is a real one: an HMAC
signature verified against the key ring of a process that got its copy from
its own Vault Agent. The board, the README and both parties' start-up logs
say this.

## Architecture

```text
 rotation controller ──CAS write──► Vault kv/shift-gear/rotation/api-key/secure-door (v54, v55 …)
                                       ▲ read                          ▲ read
                    policy sg-rotation-door-verifier    policy sg-rotation-door-client
 ┌ door-verifier (SA door-verifier) ───────┐    ┌ door-client (SA door-client) ───────────┐
 │ vault-agent  own token, no sink/listener │    │ vault-agent  own token, no sink/listener│
 │ vault-probe  reachability only           │    │ vault-probe  reachability only          │
 │ verifier     key ring; POST /enter :8080 │◄───│ client       hot reload; signs and      │
 │              /status :9090              │    │              knocks every 1 s; /status  │
 └──────────────────────────────────────────┘    └─────────────────────────────────────────┘
               ▲ :9090                                       ▲ :9090
               └──────────── door-board (Node) ──────────────┘ ◄── Route secure-door.<apps_domain>
```

- **Two identities.** Each party has its own ServiceAccount, Kubernetes auth
  role and policy. Each reads only the one secret. Neither party's main
  container holds a token, has a `VAULT_*` setting or calls Vault: in each
  pod the projected token is mounted into `vault-agent` only.
  `restricted-v2` runs all containers in a pod as the same UID, so inside a
  pod the isolation comes from the mounts; between the parties it comes from
  separate pods and identities.
- **The protocol.** The request carries `client`, `key_version`, `ts` (unix
  seconds), a random 128-bit `nonce`, and
  `sig = HMAC-SHA256(secret_v, "secure-door|<client>|<ts>|<nonce>")`. No secret
  crosses the network. The verifier answers GRANTED or DENIED with a reason:

  | Reason | When |
  | --- | --- |
  | `current` | signed with the verifier's current version |
  | `grace (vN is current)` | signed with the previous version, inside the grace period |
  | `stale-timestamp` | `ts` more than 30 s from the verifier's clock |
  | `version-unknown` | a version newer than the verifier has adopted |
  | `version-retired` | a version no longer in the key ring |
  | `bad-signature` | the HMAC does not match (compared with `hmac.compare_digest`) |
  | `replayed-nonce` | the same nonce inside the acceptance window |
  | `malformed` | anything else |

- **Cut-over modes** (`DOOR_GRACE_SECONDS`, Terraform `grace_seconds`):
  - **grace** (default 30 s): the previous version stays accepted for 30 s
    after the verifier adopts the new one, so normal rotation needs no
    refusals;
  - **strict** (`0`): the previous version is refused the moment the
    verifier adopts the new one.

  The two Agents fetch independently, so either party can see a new version
  first. When the client is first, the verifier answers `version-unknown`
  and the client signs again with the previous key it still holds (a
  *fallback*). When the verifier is first in strict mode, the client is
  refused (`version-retired`) until its own Agent delivers the new version:
  that is the measured denial window.
- **Grace lives in the verifier's memory.** A restarted verifier loads only
  the current version, so a client still on the previous one is refused
  until it reloads. The tests show this (d06).
- **A dedicated secret.** `api-key/secure-door` (`owner: application`,
  strategies `[time, event]`, every 60 s, and on every write to the core
  `app-config`). It has no usage strategy: two Agents re-reading every few
  seconds would count as usage and cause a rotation storm.
- **Last seen version.** A small PVC (client only) keeps the last seen
  version number, so a restart can report `v54 -> v58; missed 3`.

## Health: three signals per party, never one "healthy" light

| Signal | Evidence | Without evidence |
| --- | --- | --- |
| Credential loaded | the party parsed a complete snapshot (version, time) | "no credential yet" |
| Last successful Vault refresh | the party's Agent log (TRACE `successful data response`, one per fetch) | "not observable; last change rendered …" |
| Vault connectivity | the party's `vault-probe` (unauthenticated status: reachability, not authorisation) | "unknown" |

The credential state follows from evidence: `current` (loaded, Vault
reachable), `last-known-good` (Vault unreachable or sealed, or unknown),
`stale` (an Agent fetch error, or unreachable for longer than 60 s),
`no-data`, `error`. The Agent rewrites the file only when the secret changes,
so an unchanged file is never a reason to call anything stale.

## Intervals: configured vs measured

| Stage | Configured | Measured |
| --- | --- | --- |
| Rotation (`api-key/secure-door`) | 60 s, plus `make rotation-rotate` and `app-config` writes | Vault `created_time` |
| Vault created → each party adopted | `static_secret_render_interval = "5s"` per Agent | board latency table; `.build/addons/rotation/consumer-test.json` |
| Client file → client reloaded | poll 1 s | same |
| Client request | every 1 s | verdict counts on the board |

Only measured numbers are written anywhere. See
[docs/rotation.md](../../../docs/rotation.md#consumer-demo-secure-door-prompts-01_09-01_10)
for the latest run.

## Files

`consumer/secure_door/` (Python stdlib: `protocol.py`, `party.py`,
`verifier.py`, `client.py`) · `board/` (`server.mjs`, `static/`, where
`tokens.css` is generated from the console's `main.css` by
`scripts/sync-board-css.py`) · `terraform/` (its own root and state) ·
`ansible/` (the two Kubernetes auth roles, proof, removal) · `tests/`
(offline unit, board server, live suite, Playwright + axe).
