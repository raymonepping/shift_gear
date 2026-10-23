# Shift Gear — project and product requirements document

Version: 1.0 planning draft. Date: 2026-10-14. Product owner: Raymon Epping. Status: proposed requirements for the next strengthening release; not an assertion that the requirements are already implemented.

Supporting documents: [project analysis](project-analysis.md), [MoSCoW roadmap](roadmap.md), [architecture](architecture.md), [security model](security-model.md), [operations](operations.md), [testing](testing.md), [design system](frontend/DESIGN.md).

## 1. Product purpose and project objective

Shift Gear is a reproducible Vault Enterprise reference platform on OpenShift with a console that explains provisioning, configuration, secret delivery and observed health. It demonstrates how Terraform and Ansible cooperate without sharing unrestricted routine authority, and how VSO and Vault Agent deliver data without putting a Vault token in an application container.

The next project objective is to make that platform reliably observable, safely operable and recoverable while preserving its existing architecture and visual identity. Operators must be able to tell what was checked, when it was observed, which tool owns it and whether an action was merely accepted or actually completed.

The product is a reference implementation and demonstration environment. A production profile is a later, separately verified deployment configuration. This document does not turn a single CRC node into an enterprise availability or compliance commitment.

The first correction is the confirmed token-reviewer credential in foundation Terraform state (analysis F22). Keeping values out of state remains a required outcome; it is not uniformly true in the current implementation. The review inspected only field names and nonempty presence, without printing the token.

## 2. Problem statement

The platform can rebuild and converge, but its evidence, user actions and verification have uneven contracts. Snapshot-backed pages poll without creating new observations; some missing timestamps become the current time; one action has no backend; some role tests can pass against nonexistent selectors. Automation artifacts can mix runs, and rebuild proof does not establish restoration of data written after bootstrap.

These gaps make it harder to distinguish an actual Vault failure from old evidence, or a completed rotation from an accepted write. The strengthening release must close those ambiguities before expanding the management surface.

## 3. Baseline and preservation constraints

The recorded proof on 2026-10-10 includes a fresh VM plus lab in 13m17s wall time, a 9m00s lab convergence record, a 5m11s independent repeat, 18 static checks, 22 stack checks, 19 boundary assertions, 104 standard Playwright tests with TLS verification, nine scenarios, a separate failover journey and 22 screenshots. These are historical results, not a fresh test run on the PRD date. The [analysis](project-analysis.md#3-evidence-baseline-and-confidence) names the evidence and its limits.

Preserve:

- Five Terraform roots and the authoritative thirteen-phase interleaving until an explicit migration decision changes them.
- Structural Terraform state, Ansible-owned values and ordered moments, narrowly named runtime-field ownership, and VSO reconciliation.
- Four routine tool tokens with allowed and denied operations; retained bootstrap authority is separately documented.
- Main Vault transit auto-unseal through the mTLS Agent proxy; no usable seal token in the main Vault pods.
- No browser-visible Vault token, secret value, private key, root/unseal material or secret-bearing Terraform output.
- Verified TLS across existing browser, BFF, Vault, proxy and automation paths.
- Independent stdout audit device alongside the socket collector.
- The daylight-glass design system, dark hero, provenance labels and reduced-motion support.
- Explicit dry-run and operator authorization for destructive operations.

## 4. Users and jobs

| Persona | Job to be done | Product success |
| --- | --- | --- |
| Platform operator, using host tools | Build, resume, diagnose and recover the lab | Correct target and phase visible; failures are actionable; no false success or accidental runtime switch |
| Cleo, operator | Rotate the approved application secret and inspect delivery | Accepted write is correlated to VSO sync and a healthy consumer, or remains visibly unverified |
| Ada, engineer | Understand workloads, mounts, ownership and auth boundaries | Can trace a symptom to its source and next supported action without seeing credentials |
| Finn, auditor | Inspect metadata and proof provenance within the chosen access policy | Can distinguish volatile audit feed from durable proof, see gaps and dates, and inspect scoped evidence |
| Ben, staff/viewer | Understand the platform and its status | Gets useful observation without privileged controls; direct forbidden requests are denied |
| Dirk, approver | Evaluate changes using policy-appropriate information | Sees scoped evidence and denied actions; a distinct approval workflow is not implied unless implemented |
| Maintainer/reviewer | Improve Terraform, Ansible or UI without breaking the contract | Fast CI detects boundary, schema and behavioral regressions; release identifies exactly what was tested |
| Presenter/learner | Explain the architecture and run a bounded demonstration | Visual continuity, clear ownership and repeatable, dated proof rather than unsupported green indicators |

All access is ultimately subject to Vault and Kubernetes authorization. Hiding a button is not authorization. A persona label does not establish every capability that its name suggests.

## 5. Scope and priorities

### Must for the core strengthening release

M01 truthful evidence/mobile containment; M02 reliable supported actions; M03 session/logout/access contract; M04 coherent serialized runs; M05 meaningful tests/CI/proof coverage; M06 isolated data recovery; M07 task/field ownership; M08 credential and lifecycle operations.

### Should after the core behavior is stable

S01 bounded runtime observation; S02 PKI/Transit workflows; S03 application onboarding; S04 second OpenShift profile; S05 controlled dependencies/upgrades; S06 investigation UX. A Should item becomes a prerequisite if the selected Must implementation depends on it. For example, fully observed rotation requires enough of S01 to verify sync; otherwise M02 must honestly report accepted/unverified.

### Could

C01 protected HCP Terraform/AAP integration; C02 metrics/durable audit adapter; C03 one justified new secret-delivery consumer/pattern; C04 read-only policy/ownership explorer.

### Wont for this horizon

W01 general administration console; W02 browser-visible secret material; W03 unattended destructive operations/browser shell execution; W04 replacing working components or redesigning for novelty; W05 unsupported production HA/portability/compliance/DR claims. See [roadmap exclusions](roadmap.md#6-wont) for reconsideration conditions.

## 6. Required user journeys

### J01 — Open the console and judge its evidence

The visitor signs in through the existing Vault/Keycloak flow and sees Fleet. The shell shows source and observation age for its health summary. Reloading the page may retrieve newer evidence but must not change the time of an unchanged observation. If evidence is missing, malformed or stale, the UI explains that limitation without pretending Vault is definitely healthy or sealed. A useful next step is available without requiring a privileged token.

### J02 — Rotate the approved static secret

Cleo selects `app-config` and sees the intended scope and consequence: a new KV version, subsequent VSO delivery and a possible workload restart. The API authorizes the signed-in identity, applies concurrency protection and returns a safe receipt. The UI presents accepted, awaiting sync, synced and consumer-ready states only as they are observed. If proof cannot be obtained before the deadline, the write remains accepted/unverified with a verification path. Retrying must not create an uncontrolled second rotation. Ben's direct API request is denied without a write.

### J03 — Inspect Agent state

The page distinguishes seal Agent and application sidecar, their credential metadata and observation ages. The unsupported re-injection capability is disabled with an accessible explanation. No user can be offered an action that only fails as a missing route. A future implementation must have an explicit scoped mutation contract before enabling that control.

### J04 — Recover from a failed build or publication

The host operator starts a run against a verified target. Every phase and gate belongs to that run. On failure the manifest states which steps completed and the safe resume command. If the infrastructure converged but evidence publication failed, publication can be retried independently. The console shows the last successful observation with its real age and separately identifies a newer failed attempt where a trusted record is available.

### J05 — Sign out and change identity

Ada signs out, her local session is destroyed and the Vault-token revocation result is handled according to the documented best-effort policy. Ben then signs in as Ben. Provider-initiated logout is either fully supported with validated session invalidation or explicitly unsupported; acknowledging an arbitrary POST is never presented as proof of invalidation. Session expiry returns to sign-in with a useful explanation and no leaked token.

### J06 — Investigate an audit event

An authorized visitor filters a bounded list by time/path/operation/person as supported. The page states whether it is live, disconnected or unconfigured and identifies collector restarts and retention gaps. Pagination or bounded rendering keeps mobile navigation usable. The view contains approved metadata and HMAC field names, not raw secret values. Access policy is stated explicitly.

### J07 — Restore data, not merely rebuild structure

An operator previews the source and isolated destination, verifies backup identity and custody, and explicitly authorizes the recovery. The seal dependency is restored or otherwise made compatible before the main cluster is expected to unseal. A post-bootstrap canary, policies and relevant PKI/Transit data survive the restore. Original live lease consumers cannot be reached accidentally. Recovery completes only after readiness and functional verification, not after snapshot acceptance alone.

## 7. Functional requirements and acceptance criteria

IDs are stable for implementation issues and test names. “Must” below is a release requirement; it is not an instruction to perform the implementation during this documentation task.

| Requirement | Priority / roadmap | Required behavior and acceptance |
| --- | --- | --- |
| FR-01 Evidence envelope | Must / M01 | Every status response carries schema version, source mode, source identity, nullable observation time, retrieval time, run/cluster identity where applicable, availability and freshness. Fixture tests cover absent, malformed, future-dated and stale evidence. No default request time substitutes for an observation |
| FR-02 Status interpretation | Must / M01 | Component health is independent of evidence validity/freshness. Missing node counts or unknown TTL do not produce healthy/no-token claims. Shell pills use the same rules as page cards. Failed reload preserves old data only with stale/error labeling |
| FR-03 Responsive usability | Must / M01 | All pages fit the 390px document viewport with no unintended horizontal page scroll; also review 320px and 200% zoom. Navigation contains its own overflow or accessible menu. Table scrolling is local, labeled and keyboard reachable. No clipped action/error text |
| FR-04 Supported capabilities | Must / M02 | Re-injection remains disabled with an explanation until a real authorized endpoint and outcome proof exist. Unsupported actions never produce an optimistic success. Shell/footer/design documentation accurately describe the bounded rotation exception to observe-only automation |
| FR-05 Safe KV write | Must / M02 | Rotation is limited to explicitly allowed names/paths, uses the visitor's Vault token, preserves unrelated fields and uses KV v2 compare-and-set. A competing write yields a conflict. Validate retry semantics with an operation identifier/idempotency mechanism or a documented no-automatic-retry outcome |
| FR-06 Rotation result | Must / M02 | Return receipt with safe ID, target, initiating identity, accepted time and resulting version. Observe sync/version or safe marker after the write, then consumer readiness, before claiming completion. Unobservable or timed-out completion remains accepted/unverified; a timestamp change unrelated to the target version is insufficient |
| FR-07 Server authorization | Must / M02/M03 | Anonymous requests return 401, authenticated disallowed actions 403, unsupported targets 404, conflicts 409. Invalid input is rejected before mutation. Reconcile the approver/admin UI flag with operator-only mutation policy using explicit capabilities; test Dirk, Cleo and Ben. API tests prove no secret write occurred in each denied case; never rely on UI visibility |
| FR-08 Session contract | Must / M03 | Define expiry, cleanup, revoked-token behavior, trusted forwarded headers and pod-restart semantics. Single-replica memory sessions may fail closed on restart. Invalid/expired sessions cannot mutate; new login receives a new opaque ID; cookie flags are verified over actual HTTPS |
| FR-09 Logout capability | Must / M03 | Preserve initiating logout/persona switch. If provider backchannel is supported, validate signature, issuer, audience, time, event, replay and identity/session mapping; invalidate the intended sessions. Otherwise remove support claims/configuration and document limitations. Invalid messages never invalidate unrelated sessions |
| FR-10 Mutation request protection | Must / M03 | Enforce a documented allowed-origin/CSRF policy and bounded abuse protection for mutations and auth entry points. Test malicious Origin, missing/invalid required proof, expired session and repeated requests. Trusted proxy rules cannot let client headers remove Secure-cookie protection |
| FR-11 Audit access and projection | Must / M03/M05 | Owner records the audit-reader policy; default preserves current authenticated metadata access until deliberately changed. Direct read API enforces that policy. Projection is allowlisted; raw values/body/tokens are never returned. Oversized complete or partial lines are bounded before parsing; malformed records and restarts are counted |
| FR-12 Run identity and locking | Must / M04 | Every mutable command uses one agreed lock per target. Manifest includes run ID, cluster identity, input digests, phase/gate states and timestamps. Missing phase exits nonzero; failed current run cannot reuse old gate passes. Parallel mutations fail with an actionable message |
| FR-13 Publish consistency | Must / M04 | Producer validates and scans a coherent generation before publication. Publication and provisioning outcomes are distinct. Readers detect mixed file generations and reject invalid combinations. Interrupted/failing publication has a safe retry without a repeated Terraform apply |
| FR-14 Portable input digests | Must / M04 | Hash sorted relative names and bytes from a reviewed manifest including automation scripts, callback/collector, policies, Terraform/config/locks, and separate UI inputs. Same checkout at two paths yields same digest; changing a relevant executable changes it; credentials/caches/generated outputs are excluded |
| FR-15 Precise ownership | Must / M07 | Register tool/resource/runtime-field ownership and separate bootstrap exceptions. Only known task changes receive the UX exemption. A repeated build, pod deletion or unlisted task causes idempotency failure. Legitimate restart annotations survive while unrelated image/label drift is detected |
| FR-16 Dry-run coverage | Must / M07 | Each Ansible reconciliation area declares check-mode support, unsupported checks and separate proof. Skipped/unsupported is never pass. Existing four drift cases restore original state; identity/federation dry-run limitations are visible in proof output |
| FR-17 Proof and CI ladder | Must / M05 | Credential-free PR jobs run syntax/lint, Terraform mock/contract tests, UI checks and targeted fixtures/API tests. Protected live jobs execute the full baseline and serialize disruptions. Test expected roles using selectors that actually match; include positive visibility and direct negative API cases |
| FR-18 Scan and proof coverage | Must / M05 | Scanner reports required-source/target coverage and incomplete reads, recurses through configured KV metadata paths, covers delivery candidates and intended nested logs, and emits only safe labels/filenames. Add synthetic Kubernetes JWT canaries and structural state checks that detect computed credential values as well as explicit HCL values. Sanitized proof manifest records revision, digests, run/cluster IDs, scope and explicit skipped/incomplete outcomes |
| FR-19 Backup contract | Must / M06 | Inventory both Raft stores, seal/unseal dependencies, certificate trust, credential custody and external DB/identity state. Encrypt or otherwise protect backups at rest with operator-selected custody; record backup identity/age/retention and restore compatibility. Backups are excluded from public artifacts and UI |
| FR-20 Restore proof | Must / M06 | On an explicitly authorized isolated target restore required seal and main data, verify a canary written after bootstrap, policies and PKI/Transit state, then authentication/VSO/audit/HA behavior. A missing required key/dependency fails preflight. Record recovery point and elapsed recovery; do not mutate source consumers |
| FR-21 Credential lifecycle | Must / M08 | Remove token-reviewer credential values from ordinary Terraform state while retaining declarative ServiceAccount/RBAC ownership. Prove Kubernetes auth after replacement and retire the prior credential; review protected state history without automatic erasure. Inventory types/owners/metadata without values; define renewal, expiry and repair for bootstrap/AppRole/rotator credentials. Test expiry/revocation. Routine observation receives no root token; root custody is explicit |
| FR-22 TLS and lifecycle operations | Must / M08/M04 | Validate target and dependencies before mutation. Certificate rollover stages trust before leaves and checks client/server use. Down/reset report partial failures and verify postconditions before claiming completion. Distinguish helper setup, VM running, API reachable, Vault unsealed and workload ready. Finish in the operator-selected runtime state |
| FR-23 Runtime observation | Should / S01 | Bounded read-only adapter supplies source-stamped status needed by workflows. Permissions are minimum for target metadata; no broad Kubernetes Secret reads or bootstrap token in BFF. Outage/403/timeout are distinguishable and never refresh observation time falsely |
| FR-24 PKI and Transit proofs | Should / S02 | Add reversible positive/negative certificate and encryption lifecycle tests with least-privilege credentials. Show owner, last proof and expiry/rotation metadata; do not show private keys or plaintext. Destructive guards receive actual change-plan tests |
| FR-25 App onboarding | Should / S03 | A second app uses the documented connection/auth/source/destination/consumer contract and cannot read another app's paths. Reconcile intended database connection changes and prove static/dynamic delivery and recovery |
| FR-26 Environment profile | Should / S04 | Preflight capabilities, explicit storage/registry/trust/architecture, CIDR collection and topology options. CRC behavior retained. Second OpenShift baseline records actual changes and independent failure domains; no success inferred from absence of CRC strings |
| FR-27 Dependency lifecycle | Should / S05 | Reviewed lockfiles, supported versions, built/deployed digest record and controlled OLM upgrade strategy. Perform one supported upgrade after a recovery point and document whether rollback is supported or restore is required |
| FR-28 Investigation UX | Should / S06 | Source drawer, ownership/runbook links, audit filters/bounded rendering and consistent empty/loading/error/expired states. Keyboard tasks and human visual review supplement automated axe checks. Update the design spec to match implemented behavior |
| FR-29 Policy and ownership explorer | Could / C04 | Authenticated, read-only publication of declared owners/runtime exceptions and the reviewed expected-capability matrix, with source hashes and publication provenance. Local filters and runbook links; explicit unavailable/stale states. No arbitrary path/token input, policy edits or implied live authorization |
| FR-29 Optional integrations | Could / C01–C04 | Each integration has a time-boxed decision, cost/permission review and proof of compatibility with the phase/value boundary before becoming a maintained dependency |

## 8. Data, API and execution contracts

### Evidence model

The exact implementation can evolve, but it must represent independent dimensions rather than collapsing source failure and system health into the same boolean. A proposed response envelope:

```json
{
  "schemaVersion": "1",
  "source": {"mode": "snapshot", "name": "host-publisher"},
  "clusterId": "example-cluster-id",
  "runId": "example-run-id",
  "observationId": "example-observation-id",
  "observedAt": "2026-10-14T10:00:00Z",
  "retrievedAt": "2026-10-14T10:07:00Z",
  "availability": "available",
  "freshness": "stale",
  "health": "healthy",
  "reason": "observation-age-exceeded",
  "data": {}
}
```

This fixture represents a formerly healthy observation that is now stale; the UI must not display it as current healthy state. `observedAt` is null when unavailable; future/invalid timestamps are rejected. Initial thresholds are configurable per source, with a proposed 120-second threshold for operator-status snapshots; validate the threshold against the chosen publication mode. A manually published snapshot will legitimately become stale until republished. Defer automated polling reduction until this semantic model works.

Preserve the six-field cluster connection contract initially. Add version/capability/cluster-identity metadata beside it or through a reviewed compatible extension; do not silently reinterpret `pod_cidr` as a list. Secrets and access credentials never belong in either contract.

### Action model

Proposed safe progression: `accepted → awaiting-observation → synced → consumer-ready`. Alternative terminal presentation: `denied`, `conflict`, `failed-before-write`, or `accepted-unverified`. Timeouts after a possible write must not be labeled “nothing happened.” Receipt data is safe to display and contains no secret values. An operation journal, if introduced, requires persistence/retention and privacy rules.

A Kubernetes observer, if selected, belongs behind a bounded read-only interface with explicit namespace/resource selectors. The BFF cannot execute host Terraform/Ansible or use a general cluster administrator identity. Observation ownership does not transfer desired-resource ownership away from Terraform.

### Run manifest

Proposed fields: schema version, run ID, cluster ID, input revision plus dirty-tree indication, automation/UI/dependency digests, tool versions, started/finished times, phase states, gate states/scopes, skip reasons, last failure, last success reference, provisioning result and publication result. Preserve sanitized manifests long enough for releases to reference them. Keep raw logs/trace material under a separate restricted retention policy.

## 9. Nonfunctional requirements

| Area | Requirement / acceptance |
| --- | --- |
| Security | No TLS bypass, root fallback, arbitrary command execution, value-bearing state/UI/proof artifact or broadened routine token policy to make tests pass. Negative tests cover each boundary changed by the release |
| Reliability | All external calls and waits are bounded; configured timeout reports unavailable/incomplete. One failed source must not fabricate another source's health. Mutation lock is target-specific and interruption-safe |
| Performance | Planning targets: local snapshot-response p95 ≤1 s; cached UI navigation p95 ≤2 s on named test hardware; live observer per-source deadline ≤5 s unless the ADR justifies otherwise. Rotations acknowledge the write separately from delivery. Measure before declaring target met |
| Rendering | Cap initial audit rendering at 200 rows or fewer and provide bounded navigation; never append indefinitely. Observer and polling load must be measured with concurrent visits and paused/backoff behavior on failure |
| Accessibility | Retain existing WCAG 2.1 A/AA axe coverage at 1440/390 and reduced motion; add keyboard, focus, zoom, overflow and announced action-state checks. Automated checks alone are not a conformance claim |
| Recoverability | Backup freshness and restore-time objectives are selected with the operator before accepting M06. Record snapshot time, latest recovered canary and actual restore duration; no inherited SLA from clean-build timings |
| Compatibility | Define supported CLI/provider/chart/operator/architecture matrix and preserve a verified CRC profile. New official API/provider features require version-compatible proof; no automatic major upgrade |
| Maintainability | Shared evidence parser and state vocabulary; small adapters; stable resource addresses; any Terraform moves use explicit migration and empty-plan proof. Task/field exceptions have owner and test |
| Privacy | Audit metadata access and retention are explicit; sanitize errors and traces. No raw Vault responses, session objects or OIDC/logout tokens in normal logs |
| Reproducibility | Manifest identifies actual binaries/images/providers and relevant source bytes. Repeat run is unchanged except precise declared tasks; relocating the checkout does not change source identity |

Performance numbers are proposed budgets for the new work, not measurements from this documentation review. Select concurrency/load and fixture size in the test plan before comparing p95 values. Existing 9m00s/5m11s lab times remain reference measurements rather than hard release limits.

## 10. Verification and release acceptance

### Credential-free verification

Use existing `make check` and `make ui-check` plus new evidence/API/session/collector fixtures. Include missing evidence, invalid schema, old/future timestamps, mismatched run, lost session, malicious Origin, unknown target, concurrent KV update, oversized audit line and simulated publish failure. Verify wrong task changes fail even inside UX. A local path relocation must retain the same digest.

### Protected live verification

Run against a preflighted named environment: two complete labs, full drift, stack verification, boundary matrix, identity verification, standard browser suite, separate failover and screenshots, scenarios 01–09, and targeted action/expiry/certificate tests. Serialize mutable scenarios and confirm restored state after each. Preserve baseline passing behavior while adding meaningful new assertions; raw test count is not the success metric.

### Separately authorized recovery verification

Only after source/destination identity, isolation and custody are confirmed: protected backup, isolated restore, post-bootstrap canary comparison, seal dependency verification and end-to-end recovery checks. No reset/restore during ordinary PR CI. The runbook includes cleanup of only the isolated target and a final-state check for the source environment and host runtime.

### Acceptance matrix

| Journey | Requirements | Required proof |
| --- | --- | --- |
| J01 status trust | FR-01–03, FR-13–14 | Fixture/API and browser checks; missing/stale state cannot be green |
| J02 rotation | FR-05–07, FR-10, FR-23 where selected | Authorized write, denied direct API, concurrent conflict and correlated live completion or honest unverified outcome |
| J03 Agent inspection | FR-02, FR-04, FR-21 | Unsupported capability disabled; safe credential metadata and no hidden-route failure |
| J04 failed automation | FR-12–18, FR-22 | Phase/publish failure injection, lock collision, old-artifact rejection, repeat-run proof |
| J05 identity change | FR-08–10 | HTTPS cookie/session tests; Ada → sign out → Ben; provider-initiated path consistent with ADR |
| J06 audit investigation | FR-03, FR-11, FR-28 | Permission, projection/stream-bound tests, collector restart, bounded mobile browsing |
| J07 restoration | FR-19–22 | Explicitly authorized isolated recovery with post-bootstrap data and no source side effects |

Core release is accepted when all Must criteria have linked passing evidence, no unresolved violated invariant remains, and documentation distinguishes implemented capabilities from later Should/Could work. Unfinished Must scope requires an explicit release-scope decision, not a hidden skip. Supported release artifacts include sanitized manifests and source references; confidential snapshots, browser auth state and raw tokens are excluded.

## 11. Dependencies, decisions and risks

| Dependency/decision | Owner role | Required before |
| --- | --- | --- |
| Backchannel identity/session mapping or explicit withdrawal of support | Identity/security maintainer + product owner | FR-09 implementation acceptance |
| Read-only observation architecture and minimum RBAC/Vault scopes | Platform/Vault maintainer | FR-06 full delivery confirmation and FR-23 |
| Audit readership policy and metadata retention | Product owner/security maintainer | FR-11 acceptance |
| Recovery target, isolation, confidential storage/custody and objectives | Operator + Vault maintainer | FR-19–20 proof execution |
| Compatibility matrix, CI runner and protected live environment | Release/platform maintainer | FR-17/27 acceptance |
| Scope of second cluster and permission/cost | Product owner/operator | FR-26 execution |

The greatest implementation risks are scope expansion into generic administration, extra observers receiving excessive privilege, state-address churn from premature module extraction, false confidence from mock-only tests, and restoration touching live external lease consumers. The delivery increments in the [roadmap](roadmap.md#7-delivery-sequence-and-release-gates) address those risks with early contracts, target locks and separate recovery proof.

## 12. External technical references

These references inform proposed behavior; they do not prove implementation in this repository. Checked 2026-10-14. Validate compatibility against the selected installed versions during implementation.

- KV v2 provides version-aware writes using `options.cas`: [Vault KV v2 API](https://developer.hashicorp.com/vault/api-docs/secret/kv/kv-v2).
- VSO synchronizes configured sources into Kubernetes Secrets: [Vault Secrets Operator](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso).
- Provider logout requires token validation and session matching: [OpenID Connect Back-Channel Logout](https://openid.net/specs/openid-connect-backchannel-1_0.html).
- Restore requires isolated execution and completion checks: [Vault snapshot restore](https://developer.hashicorp.com/vault/docs/sysadmin/snapshots/restore).
- Check mode has module/task-dependent behavior: [Ansible check and diff mode](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_checkmode.html).
- Sensitive display redaction does not by itself remove data from state: [Terraform sensitive-data management](https://developer.hashicorp.com/terraform/language/manage-sensitive-data).

## Implementation acceptance record

Updated 2026-10-15: M01–M05, M07 and M08 passed local acceptance in complete live proof `f3a2a3db-fd21-4c5c-8584-06050379c4c5` (36/36 steps). Results include static 18/18, offline regressions 33/33, UI type/lint, desktop/mobile browsers 120/120, separate browser failover 1/1, screenshot journeys 2/2, all nine scenarios with full verification after each, three complete labs and three full drift checks. Stack verification passed 23/23 and token boundaries 19/19. Publication fault/retry separately preserved all five protected Terraform states. CRC and OpenShift remain running on the original cluster.

M06 isolated recovery is explicitly deferred by the owner and remains unfinished; no reset or restore result is claimed. The local receipt identifies the actual digest and an uncommitted working tree. A protected release still requires a matching receipt from the protected GitHub workflow on a reviewed clean revision; that workflow has not been executed here. The [Must delivery record](must-progress.md) contains exact source/run/cluster identities, implementation evidence and retained operational limits.

### Selected Should implementation, 2026-10-16

The owner selected FR-23/S01, FR-24/S02, FR-27/S05 and FR-28/S06. Runtime observation has a fixed-resource, least-privilege design; component proofs use dedicated fixtures; dependency operations distinguish stateless config rollback from data restoration; investigation UX retains explicit source/freshness semantics. Local acceptance passed all 41 ordered live steps, including 130 standard browser tests, failover, all nine scenarios and final idempotent convergence; see the [Should delivery record](should-progress.md#final-local-acceptance--2026-10-16). FR-27 acceptance covers the stateless collector upgrade/configuration rollback and scoped snapshots; it does not establish persistent-data restoration. The dirty-workspace local receipt cannot authorize a protected release, and protected live CI remains unexecuted. FR-19–20/M06 isolated restore remains deferred; selecting S05 does not silently accept that unfinished recovery journey.

### Selected Could implementation, 2026-10-17

C04 adds FR-29: an authenticated read-only explorer for declared field ownership and the approved expected-capability matrix, including source/run/cluster provenance, source-file hashes, local filtering and investigation links. Expectations must not become live access claims or session grants. No arbitrary path/token input, policy editor or additional runtime permission is allowed. Missing or malformed publications must be explicit. Acceptance requires producer/projection negatives, actual API authentication/parameter tests, auditor keyboard journeys, axe, containment and visual review; local acceptance passed 41/41 live steps, 138/138 standard browser tests and the recorded visual review. See the [delivery record](c04-progress.md#final-local-acceptance--2026-10-17) for source identities and release/recovery limits. C01–C03 are not selected.


## Selected C02/C03 extension — 2026-10-22

FR-30 (C02) requires an optional private metrics destination and bounded durable audit metadata integration, independent source states and honest freshness in the authenticated UI, fixed upstream queries, numeric metrics without sensitive labels, redaction, time/byte retention, actual access-denial checks and committed-record continuity across collector replacement. OpenTelemetry is preferred, Prometheus is an optional alternative, and the default core lab must run without either backend or archive. Disabled sources must be explicit and must cause no upstream requests; disabling runtime must preserve existing retained data. The lab-local implementation must distinguish queue/crash loss and local storage persistence from external custody or isolated restore. Acceptance is in `docs/c02-c03-progress.md`; earlier receipts cannot accept changed sources.

FR-31 (conditional C03) requires one isolated Agent-to-file dynamic-database consumer with a dedicated audience-bound identity, Vault policy, database connection/role and table scope. The application must receive neither a Vault token nor a Kubernetes Secret/JWT. Acceptance requires actual allowed/denied SQL, cross-consumer Vault denial, credential replacement and principal retirement, pod recovery and a comparison with VSO. General onboarding remains deferred.

Other unfinished work remains deferred by owner: M06, S03, S04, C01 and protected release execution. C04 remains previously accepted for its recorded inputs.

FR-30/C02 and FR-31/C03 were locally accepted on 2026-10-22: 43/43 live steps, 148/148 standard browser tests, dedicated failover, all nine scenarios and final idempotent convergence. Disabled/OpenTelemetry/Prometheus choices were exercised separately; C03 proved actual isolation, replacement, principal retirement and pod recovery. Exact source/run/cluster identities and limits are in [the final delivery record](c02-c03-progress.md#final-local-acceptance--2026-10-22). This accepts the selected lab features; external OTLP delivery, isolated persistent-data restore and protected release remain outside that result.
