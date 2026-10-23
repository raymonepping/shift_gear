# Shift Gear — strengthening roadmap

Date: 2026-10-14. Status: M01–M05, M07 and M08 delivered and local acceptance passed (36/36 steps); M06 recovery deferred by owner; protected release execution remains separate; see [Must delivery record](must-progress.md) for observed proof and deferred scope. Product owner: Raymon Epping. Delivery roles below are proposed responsibilities, not named staffing commitments.

Latest acceptance, 2026-10-22: C02 and C03 delivered and locally accepted with 43/43 live steps and 148/148 standard browser tests. OpenTelemetry is preferred; telemetry backends and archive retention remain opt-in. Other unfinished work is deferred by owner. See [the delivery record](c02-c03-progress.md#final-local-acceptance--2026-10-22).

Basis: [complete project analysis](project-analysis.md). Requirements and release tests: [PRD](PRD.md). This roadmap extends the proven platform; it does not replace the completed, Git-ignored `prompts/roadmap` execution history. Planning here does not authorize a cluster reset, restore, external deployment or paid service.

## 1. Direction

Make Shift Gear easier to trust, recover, demonstrate and extend while preserving its central contract: Terraform owns structure, Ansible owns ordered configuration and values, Vault enforces routine credential boundaries, and VSO delivers application secrets. The console should explain those boundaries and show exactly what has been observed.

Keep the existing design system and five-root structure initially. Improve behavior before adding features. The next release should let an operator distinguish a live failure, old evidence, a denied request and an incomplete action without reading source code.

## 2. MoSCoW rules

| Priority | Meaning for this roadmap | Release rule |
| --- | --- | --- |
| Must | Necessary for the next trusted-operations release | All Must acceptance criteria pass or scope is explicitly renegotiated before release |
| Should | High-value follow-up that strengthens component depth or portability | May follow the core release; omission is recorded |
| Could | Useful extension after Must/Should work has evidence | Time-box a decision or prototype; no implicit commitment |
| Wont | Won't do in this roadmap horizon | Reopen only through a requirements decision |

Priorities are value and risk judgments about the next iteration. They do not relabel the existing successful lab as failed. No item is complete merely because a card exists, a test is scheduled, or a mocked provider accepts a resource shape.

## 3. Must

Owner scope decision, 2026-10-14: isolated recovery M06 is deferred for now. It remains unfinished and is excluded from the current proof run; no restore result is claimed. Other Must criteria remain required.

| ID | Outcome and scope | Main components | Exit evidence | Dependency / proposed lead |
| --- | --- | --- | --- | --- |
| M01 | Truthful evidence and usable small-screen shell. Versioned envelope; runtime validation; distinct live/snapshot/missing/invalid/denied/stale states; observation age; no invented current timestamps; mobile containment; unsupported capability shown honestly | Evidence producer/types/readers, Fleet/Cluster/Agent/Operator, AppShell | Missing/malformed/expired snapshot never shows healthy; reload preserves observation time; 390px document width is bounded; 320px and 200% zoom reviewed; scoped tables remain keyboard-scrollable | Start first; UI + automation |
| M02 | Reliable application actions. Disable unsupported re-injection; make KV rotation concurrency-safe; separate accepted/synced/ready states; accessible errors and safe retry; direct endpoint authorization | Operator/Agent pages, rotation BFF route, Vault KV policy | Cleo can perform allowed action; Ben/anonymous cannot via direct HTTP; stale snapshot cannot claim completion; conflicting KV writes return a conflict instead of overwriting; no value returned | M01 contract, M03 protections, M05 tests; UI + Vault |
| M03 | Explicit session, logout and audit access contract. Validate or stop advertising provider backchannel handling; define single-instance sessions, proxy trust, expiry cleanup and mutation origin policy; audit metadata access decision | OIDC routes, session store, BFF mutations, collector read path | External logout behavior matches the documented capability; invalid/replayed tokens rejected if supported; forged requests denied; expired/revoked sessions fail closed; successful persona switch retained | Identity design decision first; security + UI |
| M04 | One reliable automation run. Shared lock, cluster/run identity, complete input digest, failure/status manifest, success/publication distinction, bounded lifecycle postconditions | `lab.sh`, wrappers, digest, evidence publisher, down/up/reset | Concurrent mutations rejected; missing phase fails nonzero; failed last attempt visible beside last success; relocated checkout has same input digest; gates from another cluster/run cannot make the current run green | M01 schema; automation |
| M05 | Meaningful verification and release evidence. Fix vacuous selectors; add API/collector/contract negatives; PR CI; protected live ladder; sanitized proof manifest; scan source coverage | Tests, check scripts, secret scanner, workflows, release checklist | Seeded regressions fail; all baseline and new tests pass; required scan source failure reports incomplete; new/staged delivery files covered; release links tested revision and run IDs | Cross-cutting; begin with M01–M04; QA + automation |
| M06 | Data-preserving recovery, separate from rebuilding. Capture/protect both Vault Raft stores and recovery dependencies; isolated restore; post-bootstrap data verification | Seal/main Vault, snapshot workflow, recovery runbook | Restored seal dependency and main cluster can read a canary written after bootstrap; policies/PKI/Transit checks pass; destination isolation verified; elapsed loss/recovery measured | M04/M05/M08; Vault + platform |
| M07 | Enforced tool and field ownership. Named runtime-field ownership, task-level UX change exception, check-mode coverage, policy-derived boundary matrix | Terraform lifecycle, Ansible stats, idempotency/drift/boundary | Legitimate VSO/Ansible annotation survives; image/label mutation still detected; unexpected UX build/change fails; unsupported checks cannot be reported as passed | M04/M05; Terraform + Ansible |
| M08 | Operable credentials and lifecycle. First remove the confirmed token-reviewer JWT from Terraform-managed value state; then safe metadata inventory, expiry/repair, staged trust, root custody and truthful host/VM/API/Vault states | Bootstrap tokens, AppRole/rotator, TLS, token reviewer, lifecycle scripts | State has no reviewer credential; replacement/revocation and protected-history handling recorded; Kubernetes auth remains functional; expiry and certificate drills pass; no silent host runtime switch | Reviewer correction starts immediately with M05/M07 guards; broader drills need M04; Vault + automation |

### Must implementation notes

**M01:** Observation validity is distinct from component health. Use an orthogonal source/availability/freshness model, not one overloaded status string. The UI may show an old healthy result only as a clearly dated historical observation. The first slice can make existing snapshots honest before adding any new observer.

**M02:** The safest first re-injection fix is a disabled capability with recovery guidance. This roadmap does not require a new cluster mutation API. For rotation, write acceptance is useful progress even if sync cannot yet be observed. VSO delivery proof needs version/marker correlation and an observation after the write; a different `lastSyncTime` by itself is insufficient. Preserve unrelated KV fields through compare-and-set.

Resolve the approver/admin mismatch at the capability level: the session API currently treats the approver as admin while rotation accepts operator/root. Tests must include Dirk and must not resolve the mismatch by granting unnecessary Vault permissions.

**M03:** Vault mediates OIDC and the BFF does not currently retain an ID token or provider `sid`. Record an ADR before choosing a signed logout-token-to-session mapping. If the mapping cannot be made reliable, explicitly withdraw backchannel support claims/configuration and document local logout behavior while preserving the working initiation flow. Never accept an unsigned token as a convenience.

**M04:** A provisioned cluster and published evidence are separate outcomes. A publication retry must not rerun a successful infrastructure apply. Conversely, a previous successful manifest must never hide the latest failed attempt. Destructive commands remain separate and require target identity, dry-run preview and explicit operator authorization.

**M05:** PR CI is credential-free. Live jobs use a protected environment and concurrency lock. Browser authentication artifacts, traces and logs require redaction/retention controls. Synthetic leak tests use fixtures, not actual secret material. Keep the 19 existing boundary assertions and add justified cases rather than treating the number 19 as the permanent product goal.

**M06:** A snapshot file is confidential data and never a public proof artifact. Keep it outside Git, `.build/`, UI evidence and public CI downloads. Restore into isolation so old leases cannot revoke credentials on the source environment. Restore proof must include the seal transit dependency, not only the main cluster.

**M07:** Publish desired field, owner, writer, allowed runtime mutation and detection method. Check-mode gaps can be separately verified rather than pretending every task supports dry-run. Preserve bootstrap root authority as an explicit exception with custody, rather than weakening routine tool policies.

**M08:** The reviewer JWT in foundation state is a confirmed violation of the intended boundary, not an optional identity modernization. Keep ServiceAccount/RBAC structure declarative, move credential value handling out of state or use a proven projected/local identity, then verify Kubernetes auth and deliberately retire the old token. Protect and review existing backups/archives; do not erase evidence or files automatically. Rootless routine observation should be the target, but emergency recovery must remain possible and rehearsed.

## 4. Should

Owner selected S01, S02, S05 and S06 on 2026-10-16. S01, S02 and S06 are implemented and locally accepted; S05's selected stateless upgrade/configuration-recovery scope is accepted. The [Should delivery record](should-progress.md#final-local-acceptance--2026-10-16) records the passing 41-step proof and limits. M06 isolated persistent-data restore remains deferred; S05 does not close it. Protected live CI remains unexecuted. S03/S04 remain unselected.

| ID | Improvement | Deliverable and acceptance | Dependencies / proposed lead |
| --- | --- | --- | --- |
| S01 | Bounded runtime observation | Read-only status adapter or publisher with least privilege, source age and timeouts. Prove Vault/identity/observer outage behavior. No bootstrap token, broad Secret-read or cluster-admin rights in the BFF. Support the M02 safe progress model without polling an unchanged ConfigMap | M01–M05; platform + UI |
| S02 | PKI and Transit component depth | New reversible proofs: issue/verify/revoke/expire client cert; reject wrong name/policy; encrypt/decrypt, rotate, rewrap, retain ability to decrypt old ciphertext. Verify guardrails on destructive plans. No private key/plaintext in state or browser | M05–M08; Vault |
| S03 | Application onboarding contract | A second sample app follows a parameterized VaultAuth/connection/Secret/consumer pattern with namespace-scoped access. Static and dynamic recovery tests prove other apps cannot read its paths. Document DB root-rotation and connection-change behavior | M02/M05/M07/M08; Vault + Terraform + Ansible |
| S04 | Second OpenShift profile | Capability preflight, storage/registry/architecture/trust settings and multi-CIDR decision. Preserve the CRC profile; add a multi-node profile with actual failure-domain controls. Run the baseline on an explicitly provisioned second cluster and record any upper-layer changes | M04–M08; platform |
| S05 | Controlled dependencies and upgrades | Reviewed provider lockfiles, compatibility matrix, immutable deployed image identity, OLM approval/version strategy and pre-upgrade snapshot. Perform one supported upgrade and recovery rehearsal. Separate rollback of config from restoration of incompatible data | M05/M06/M07; release + platform |
| S06 | Investigation-focused UX | Shared evidence/source drawer, cross-links from failure to owner/resource and runbook, audit filters/paging with restart marker, consistent loading/empty/error states, session-expiry notice and keyboard journeys. Preserve daylight-glass tokens and one ink hero; review design spec against implementation | M01–M03/M05; UI + operator |

## 5. Could

| ID | Optional direction | Decision test | Prerequisites |
| --- | --- | --- | --- |
| C01 | HCP Terraform / AAP delivery and workload identity | Demonstrate the same interleaved phase contract in a protected pipeline, inject short-lived credentials and document emergency recovery. Use five state boundaries initially; estimate service cost before adoption | M04–M08, S05; separate account/service authorization |
| C02 | Metrics and durable audit integration | Opt into OpenTelemetry (preferred) or Prometheus, with independently optional bounded metadata retention; default core lab requires neither. Prove access/retention/redaction, disabled operation and UI source states. Preserve live-buffer semantics and retained data when disabling runtime | M03/M05, S01/S06 |
| C03 | Additional secret consumer or delivery pattern | Use one isolated Agent-to-memory-file database consumer. Compare isolation, token custody, lease replacement and pod recovery against VSO; prove actual SQL and cross-consumer denials without adding unused engines | S02; dedicated identity/fixture and licence/version capability check |
| C04 | Policy and ownership explorer | Read-only visualization of declared ownership and an approved capability matrix, with provenance. Never an arbitrary path/token browser or policy editor | M01/M03/M07, S06 |

C04 was selected and locally accepted on 2026-10-17: its read-only explorer passed all 41 live-proof steps and 138 standard browser tests. The [C04 delivery record](c04-progress.md#final-local-acceptance--2026-10-17) records exact source/proof identities and limits. At that point C01–C03 were unselected; the later owner decision below selects C02/C03.

Owner scope decision, 2026-10-22: select C02 and conditionally C03. Defer the other unfinished items (M06, S03, S04, C01 and protected release handoff). Track implementation and acceptance in the [C02/C03 delivery record](c02-c03-progress.md). Earlier completed work stays completed; its receipts remain bound to their original inputs.

Could items are experiments until the decision test passes. A prototype does not silently become a maintained production dependency.

## 6. Wont

| ID | Excluded for this horizon | Reason / condition to reconsider |
| --- | --- | --- |
| W01 | A generic Vault, Kubernetes, Terraform or Ansible administration console | Would enlarge privilege and ownership surface. Reconsider only with a separate product scope and threat model |
| W02 | Raw tokens, root/unseal material, passwords, private keys or plaintext payloads in UI evidence, browser storage or downloadable proof bundles | Violates the product's security boundary; no routine exception |
| W03 | Automatic production resets/restores, browser-driven shell commands or unattended destructive changes | Reversible diagnosis and explicit target-bound operator authorization remain required |
| W04 | Replacing Vault/VSO/Keycloak or a large framework rewrite to pursue visual novelty | Existing architecture and visual system are strengths; require demonstrated unmet behavior first |
| W05 | Claims of host-level HA, universal portability, regulatory compliance or multi-region DR from the single CRC proof | Require dedicated topology, independent environments and measured proof. Enterprise DR/replication needs a separate licence/infrastructure decision |

## 7. Delivery sequence and release gates

These are dependency-based increments, not promised calendar dates. Estimated effort and dates are set after owners assess each slice and confirm the available runner/cluster capacity.

| Increment | Included work | Reviewable output | Exit gate |
| --- | --- | --- | --- |
| I0 — establish baseline and close state exception | Source snapshot, historical-proof inventory, target/runtime identification, test map; first M08/M07 reviewer-token correction with M05 guards | Baseline manifest, reviewer credential outside current state, old-token/history handling plan; no reset | Credential-free checks and state assertions; authorized token replacement plus Kubernetes-auth verification; no mislabeling of historical evidence |
| I1 — truthful console | M01, M02, M03; targeted M05 cases | Source/freshness states, disabled unsupported actions, reliable rotation receipt, session ADR, mobile shell | Negative API/browser fixtures and target-bound live rotation proof; persona switch and verified TLS retained |
| I2 — trustworthy automation | M04, M07 and M05 completion | Lock, run manifest, publish retry, complete digest, field/task ownership, CI | Two full labs, full drift and boundary; injected phase/publish failures; concurrent-run rejection |
| I3 — recoverable platform | M06, M08 | Protected snapshots, isolated restore and expiry/CA drills, documented custody | Post-bootstrap data restored; seal dependency verified; both stacks healthy; no source-cluster side effects |
| I4 — deeper Vault workflows | S01–S03, S06 | Correlated observation, PKI/Transit scenarios, second app, investigation UX | New scenarios plus existing 01–09 pass; browser actions prove outcomes rather than visibility alone |
| I5 — portable controlled release | S04–S05; select Could decision if capacity remains | Second-cluster and upgrade proof, release manifest | All Must accepted; second-cluster limitations explicit; artifact identity and rollback/recovery documented |

M01/M03 contracts can be designed while M04 is implemented, and credential-free checks can run concurrently. Mutable live operations must share a lock; test independence does not justify running leader deletion and secret-recovery drills together.

### Global definition of done

Every item has linked PRD requirements, targeted positive and negative tests, observed release evidence, updated user/operator documentation and a rollback/recovery note proportional to its risk. Existing phase order, verified TLS, scoped tokens, app token isolation, two audit devices and value-free UI/state boundaries are retained. No previous green run is used to excuse a new failing invariant.

For the core release, run `make check`, `make ui-check`, two complete labs, full `make drift`, `make verify`, `make boundary`, identity verification, standard Playwright, separate failover, screenshots and scenarios 01–09. Then execute any newly introduced recovery/expiry/action tests on the explicitly authorized target. Destructive rebuild/restore proofs are not automatic PR checks.

## 8. Decisions, risks and measurement

| Decision/risk | Default proposal | Evidence that closes it |
| --- | --- | --- |
| Backchannel session mapping through Vault OIDC | ADR and explicit capability; prefer honest unsupported behavior over an unvalidated receiver | Provider-initiated logout actually invalidates intended sessions, or capability is removed and documented |
| Live observation architecture | Keep snapshots as default; add a bounded read-only adapter only where workflow completion needs it | Source contract, minimal RBAC/Vault policy and outage tests |
| Audit metadata readership | Owner explicitly selects all authenticated users or auditor/operator restriction | Persona matrix, direct API tests and explanatory copy |
| Session scaling | One BFF replica; restart signs users out | Restart/expiry tests; reconsider shared store only for multi-replica need |
| Snapshot custody | Protected external storage selected by operator; never Git/public evidence | Restore-access rehearsal, retention policy and sanitized manifest |
| Existing broad local privilege | Document and bound it; short-lived pipeline identity later | Boundary probes plus no root dependency in new routine observation |
| Scope expansion | Must items finish before optional integrations | Requirement traceability and release review |

Track accepted-but-unverified actions, stale/missing observations, failed publication attempts, mutation lock conflicts, unexpected Ansible changes, secret-scan coverage, test failures caught before merge, backup age and observed restore time. Baseline performance is the saved 9m00s fresh lab and 5m11s repeat; neither is an availability promise. Proposed budgets and acceptance thresholds are in the PRD and must be measured on named environments.

C02 scope refinement (2026-10-22): prefer optional OpenTelemetry, retain optional Prometheus as an alternative, and require a default core lab without either integration. Archive retention is independently optional. Runtime disabling must preserve existing data. See [configuration and limits](observability.md).

C02/C03 final local acceptance passed on 2026-10-22: all 43 ordered live steps, 148 standard browser checks and the recorded visual review. C03 is feasible and complete for the isolated Agent database fixture. Deferred scope and protected-release limits are unchanged; see [the final delivery record](c02-c03-progress.md#final-local-acceptance--2026-10-22).
