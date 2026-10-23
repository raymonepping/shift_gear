# Policy and ownership explorer — C04

The authenticated `/explorer` page presents declared field ownership and selected expected maintenance capabilities. It is read-only and available to the same signed-in personas that can view published evidence, including auditors. C01–C03 are outside this change.

## Declaration sources

`policies/ownership-map.json` is the versioned ownership registry. Each row names the desired-state owner, scope, runtime writer, exact exception/limit, verification method and contextual investigation section. Keep it aligned with [ownership operations](ownership.md) when a writer or exception changes.

`policies/boundary-matrix.json` remains the existing reviewed operation registry used by `make boundary`. The explorer publishes its 19 selected expectations without changing that registry or expanding a policy. Identity labels name the four scoped maintenance identities; they are not token values or the current browser user's permissions. This matrix is not the complete ACL of any identity.

`make ux` publishes both registries into the normal evidence snapshot. The publisher projects only named fields and records the SHA-256 of each exact source file, its fixed repository path and the current automation input digest. These hashes identify source bytes; they are not a cryptographic signature of review approval or proof of actual access. Source changes require normal review, tests and a new publication.

## Observation and authority

The page shows publication time, cluster/run/observation IDs, publication input digest and source hashes. Freshness is labelled as measured at the last reload; the shared evidence notice continues to age the snapshot. Reload reads the mounted publication and does not execute automation, renew evidence timestamps or perform live capability checks. A historical declaration remains historical even if a newer automation attempt exists.

The authenticated `GET /api/v1/explorer` reads the existing evidence mount, validates the bounded declaration shape and returns a fixed projection. Unknown properties never enter its response. A missing or invalid declaration makes only the explorer unavailable; it does not fabricate rows or permissions. Unauthenticated requests are refused, query parameters are rejected, and no write endpoint is added. No Vault call, new token, RBAC grant, policy-edit API, filesystem selector or arbitrary path lookup is involved. The declared-path search filters published rows locally.

To establish actual access, run the existing host-side `make boundary`; use `make observer-boundary` for the five named Kubernetes observations across `sg-workloads` and `sg-vault-seal`. Those results must be interpreted with their own source/run/cluster identities. The explorer does not imply their success from matching declarations or a UI role. For a field dispute, follow the linked runbook and reconcile through its declared owner.

## Validation

C04 adds producer/projection tests for exact-byte source provenance, extra-field exclusion, missing/malformed data, duplicate rows, bounded collections, invalid identities and unsupported expectations. Browser coverage checks anonymous denial, real source equality/hashes, rejected parameters/writes, auditor keyboard journeys, empty filters, unavailable publication and failed-reload recovery. The page is included in standard axe scans, narrow viewport containment and desktop/mobile screenshot capture. Delivery status and exact acceptance identities are recorded in [the C04 delivery record](c04-progress.md).
