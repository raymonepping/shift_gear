# Must delivery record

Updated: 2026-10-15. Scope: [M01–M08](roadmap.md#3-must). M01–M05, M07 and M08 are implemented and passed local acceptance. M06 isolated recovery remains unfinished and explicitly deferred by the owner. Protected GitHub release execution is separate from this local result.

| Item | Delivered implementation | Observed verification |
| --- | --- | --- |
| M01 | Versioned source/age/availability metadata; future and malformed nested snapshot rejection; matching generation checks; real observation timestamps; responsive shell, panels and grids | Offline contracts and desktop/mobile browser tests passed, including accessibility and document containment after data loads at 390, 320 and 195 CSS pixels. The last width models effective 200% zoom width; native browser zoom was not measured |
| M02 | Unsupported re-injection disabled; narrow operator KV permission; operation receipts and safe retry; field preservation and CAS; accepted/unverified delivery language | All five personas exercised allowed/denied direct endpoints; forbidden requests leave KV metadata unchanged. Rotation receipt, retry and concurrent version-ordering tests passed. Dirk retains his declared operator membership |
| M03 | Documented session contract; bounded TTL store; exact configured Origin; proxy-independent Secure cookies; signed issuer/audience/event/time/replay logout checks; subject mapping; Keycloak ingress trust | Actual provider logout invalidates a second BFF session on desktop and mobile. Invalid claim/audience tests pass. Expired saved browser sessions are replaced and cached privately; login entrypoint failures report their HTTP status |
| M04 | Target lock across nested workers/scenarios; run/cluster identity; complete relative input digest; last attempt/last success distinction; independent bounded publication/retry; destructive target UID guard | Lock contention, descriptor cleanup, unchanged/changed kubeconfig and relocation regressions pass. Three complete labs and three full drift checks passed in one receipt. Publication fault/retry separately passed with all five actual protected Terraform state files byte-for-byte unchanged |
| M05 | Behavioral and negative tests; required-source secret scanning; credential-free PR workflow; protected live ladder; sanitized source-bound receipts; protected-receipt release requirement | Complete local ladder passed 36/36 steps: static 18/18, offline 33/33, UI type/lint, browsers 120/120, separate failover 1/1, screenshots 2/2, all nine scenarios and final convergence. Protected GitHub execution has not been performed |
| M06 | Deferred by owner | No isolated target/storage selected; no snapshot restore or reset performed. Recovery acceptance remains unfinished |
| M07 | Exact named UX task exemption based on callback events; field ownership/check-mode registry; centralized token boundary matrix | Repeated lab idempotency, all five Terraform plans, full Ansible drift and 19/19 token boundaries passed. Scenario 08 detected and restored four real reversible mutations across Terraform, Keycloak and LDAP ownership |
| M08 | Reviewer JWT removed from current state; projected reviewer identity; fresh auth before old Secret retirement; custody guidance; metadata diagnostics; expired SecretID repair/revocation; staged same-root leaf renewal; truthful CRC lifecycle | Fresh Kubernetes auth and current-state audit passed. Expiry/replacement/predecessor-reuse and served-certificate/all-member rolling checks passed. Real cold stop/start preserved kubeconfig and original cluster identity, followed by full verification. Root CA migration is documented, not rehearsed |

## Completed local proof

The source-bound receipt at `.build/proof-manifest.json` records:

| Field | Value |
| --- | --- |
| Result / steps | `pass`, 36/36 exits zero |
| Proof ID | `f3a2a3db-fd21-4c5c-8584-06050379c4c5` |
| Started / finished (UTC) | `2026-10-15T09:19:05.051524+00:00` / `2026-10-15T10:03:38.624336+00:00` |
| Input digest | `74dcea050ef52bb5284723c9010c25e02c956aa95c9e4d0265c7983e58933c32` |
| Final run ID | `d3bbe098-c146-4a17-981d-4b4c3db0a8a8` |
| Cluster UID | `bef1f3e7-a9c6-43bb-9847-a0ee756cd38c` |
| Base revision / working tree | `4286faf00998e10893c8fc36cbafd440f17b049f`, `dirty=true` |
| Recovery scope | `deferred by operator` |

The receipt covers credential expiry and same-root certificate renewal; two initial labs; drift, full verification, boundaries and identity; standard browsers, separate browser failover, another verification/drift and screenshots; scenarios 01, 02, 03, 04, 06, 07, 08, 09 and 05, each followed by full verification; then final lab and full drift. Full stack verification passed 23/23. Offline coverage comprises 22 Python, six UI utility and five collector tests. The final lab recorded provisioning and publication success with all three gates passing against the same digest and cluster/run identity.

Per-step private logs are in `.cache/proofs/f3a2a3db-fd21-4c5c-8584-06050379c4c5/`. Additional diagnostic logs are in `.cache/must-2026-10-14/`. These are confidential local material, not public release artifacts. `.build/must-publication-proof.json` separately records the publication fault/retry proof against earlier run `5580c18a-fb38-46a8-a1b4-194f14f3d70d`, including comparison of all five actual protected state files.

The working tree is uncommitted. This passing local receipt is rejected as a protected release receipt by design. Before tagging, execute the protected workflow on a reviewed clean revision and retain its matching sanitized receipt; workflow configuration alone does not prove GitHub execution.

## Repairs established by the proof

Earlier failed attempts remain failed; the final receipt supersedes their open acceptance status. The important repairs were:

- Saved browser sessions invalidated by provider logout are refreshed once and reused, avoiding repeated login amplification. Both real provider logout and the complete default browser sequence passed together.
- Scenario 01 now waits for all three actual unsealed members and the public HA/Raft postconditions before reporting success. Pod rejoin alone had allowed verification to race Route recovery.
- CRC control commands use a private temporary kubeconfig. `crc stop` previously removed entries from the inherited project configuration, breaking nested cold-start lock handoff. A destructive control stub verifies preservation on success and failure; the real cold-start scenario also fingerprints the project config across shutdown.
- Lock inheritance requires verified ancestor ownership and unchanged kubeconfig bytes. Changed configuration requires fresh target resolution; unresolved configured targets fail closed rather than taking a bootstrap lock.
- CRC startup detaches its process group so the hypervisor survives controller exit. Node clock repair removes an invalid chrony directive, verifies daemon activity and bounds host/node offset. The proof holds a macOS idle-sleep assertion; explicit host suspension still requires clock repair and a new proof.

Final read-only check confirmed CRC VM **Running** and OpenShift **Running (v4.22.14)** with the original cluster UID. No reset, restore, host runtime switch, commit, push or Git publication occurred. The existing VM disk and PVC data were preserved.

## Operational limits retained

Published status is a snapshot, stale after 120 seconds. Audit remains metadata in a bounded, volatile collector. The BFF is a single replica with memory-only sessions. Rotation acceptance does not prove delivery. Historical state and private TLS backups remain confidential under operator custody. Isolated data recovery and root trust migration require their own evidence. M06 remains deferred rather than passed.


## Release handoff checked 2026-10-16

Read-only GitHub inspection found zero repository self-hosted runners, no `shift-gear-lab` environment and no published `live-proof.yml` workflow. Protected execution cannot yet be dispatched. The [release checklist](release-checklist.md) now covers clean-revision review, runner/environment setup, workflow dispatch, receipt verification and tagging the exact tested revision. Changelog entries and article `06.md` include the strengthening work; the earlier measured rebuild results are retained. No remote configuration or Git publication was performed.
