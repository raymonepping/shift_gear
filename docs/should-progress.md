# Selected Should delivery record

Started: 2026-10-16. Scope: S01, S02, S05 and S06 from the [roadmap](roadmap.md#4-should). Selected scope completed and locally accepted on 2026-10-16; see the final acceptance record below. M06 isolated restore remains owner-deferred; no restore or reset is authorized by this selection.

| Item | Current implementation | Acceptance result |
| --- | --- | --- |
| S01 | Independent TLS-verified, deadline/size-bounded probes of Vault active-service health and identity discovery; GET-only observation of four named VSO/deployment resources; coalesced ten-second server cache; foreground polling/backoff | Passed: negative source/transport contracts, ten live RBAC checks, real endpoint and full frozen-source ladder |
| S02 | Dedicated non-exportable Transit proof key, short-lived PKI issuance role and five-minute proof identity; encryption/decryption/rotation/rewrap/old ciphertext, name/policy denial, chain/revocation/expiry proof | Passed: 18 live fixture checks, destructive-plan refusal and complete baseline recovery |
| S05 | Provider lockfiles admitted to version control; routine Terraform init readonly; PKI/Transit mount destruction guards; Manual OLM approval; scoped two-minute snapshot download identities for both Raft stores; immutable collector upgrade target | Passed: private snapshot inspection, stateless upgrade/config rollback, final baseline and immutable active-image inventory. Isolated data restoration remains deferred under M06 |
| S06 | Runtime source disclosure, source/run/cluster identifiers, contextual investigation guide, audit path/type filters with paging and restart marker, session expiry notice and keyboard journeys | Passed: UI type/lint, 130 standard browsers, separate failover, screenshots and desktop/mobile visual review |

The 2026-10-15 Must receipt remains historical proof of digest `74dcea050ef52bb5284723c9010c25e02c956aa95c9e4d0265c7983e58933c32`. That receipt does not certify the new Should implementation; the replacement receipt below does.

## Initial validation and deployment

Pre-apply checks passed: static 18/18, offline 37/37 (23 Python, nine UI utility/HTTPS, five collector), UI type-check/lint. The first lab repaired an observed Multus Unauthorized CNI failure by restarting its daemonset, then failed at bootstrap token renewal: lookup returned HTTP 200 for expired periodic token metadata, while renewal returned HTTP 400. Bootstrap repair now examines TTL/renewability, persists replacements before retiring old accessors, and keeps values suppressed. This attempt is not counted as passing acceptance; its private log is `.cache/should/first-lab.log`.


The next lab passed all Ansible idempotency phases and found legitimate OpenShift-owned registry references on the new observer ServiceAccount. The correction preserves only those references and the exact registry annotation; it does not exempt RBAC or arbitrary metadata. All ten actual observer RBAC allow/deny checks passed. The live credential metadata check showed all four bootstrap tokens renewable with positive TTLs. The release validator now shares the exact ordered ladder with execution and rejects duplicated scenarios, missing postcondition checks, reordering and failed steps.

The corrected baseline passed all phases and gates with provisioning/publication success: run `93f80dec-b8b7-4e21-af2a-bbe2f73fe27d`, digest `cf6e2678e358…`, original cluster UID preserved. Subsequent source refinements require new acceptance. The first component issuance probe was correctly denied because direct root-to-child namespace token creation needs elevated permission. The dedicated proof policy/role now issue in root with exact child fixture paths, without sudo or root-policy fallback. Latest credential-free checks passed 18 static and 41 offline cases (25 Python, 11 UI/HTTPS, five collector), plus UI type/lint. Live selected proofs were still pending at that stage.

## Targeted live acceptance

- Dedicated PKI/Transit proof passed all 18 checks. This Vault build returns HTTP 200 for Transit rotation; the proof also requires a strictly newer ciphertext version and successful decryption of old/rewrapped ciphertext, rather than relying on a response code alone.
- Platform destroy plan was refused by `prevent_destroy`; no apply ran.
- Both private Raft snapshots passed structural inspection and scoped-reader capability checks. The receipt explicitly records `restoreProven=false`.
- Stateless collector Node 22 → 24, rollback with resumed audit delivery, and final re-upgrade passed. No persistent-data downgrade/restore ran.
- Inventory passed all active pods and current Deployment/StatefulSet/CronJob templates with zero mutable references. Six historical tagged references remain recorded in finished Job pods; history was preserved.
- All ten investigation browser journeys passed on desktop/mobile after correcting decorative refresh-icon naming and making expiry notices reactive to loaded session data. Runtime upstream faults use fixed reason labels; shared page feedback supports keyboard retry and retained-data semantics.

The first complete 41-step source-bound ladder stopped at the standard browser gate. Targeted passes do not replace a final passing receipt. Standalone proof receipts invalidate older success at start and record failure, including cleanup or changed-input failures. Public ladder receipts use relative scenario paths.


First full acceptance failed: proof `2fd44a39-4f3e-4ea3-833b-0556ca7b35da`, input digest `86a46295846b826943e3c126bcab1f2675f308ba0801999f8303cc050864a850`. Steps 1–15 passed, including selected live proofs, two idempotent labs, drift, verification, token boundaries and identity. Standard browsers passed 129/130; desktop Chromium found document overflow on `/audit` at 195 CSS pixels. A focused rerun reproduced the overflow and identified expansion of the audit grid. Explicit zero-minimum grid tracks now constrain the page and panel while preserving the table scroll region; browser revalidation and a new complete receipt were required. Documentation and article updates are outside the source digest.

The first containment correction passed `/audit`, exposing a second fixed-width grid on `/engines` at the same 195-pixel viewport (15/16 focused cases passed). Engine cards now cap their minimum track size at the available width and wrap plugin metadata. Snapshot-derived engine cards also label their source as Snapshot. Final validation was still pending at that stage.

Containment corrections passed all 16 focused desktop/mobile browser cases, including 390, 320 and 195 CSS pixels across seven routes. UI type-check/lint and whitespace checks passed. This targeted result does not replace the full 41-step receipt.

Replacement full acceptance passed: proof `209adbc4-ca55-41ae-9b6a-168dce3f8db8`, digest `3155a2cc2cc3eb93f679ce660a3179ff8a27fbea99575d313f90a55b5cc3667c`. Executable inputs stayed unchanged throughout the run.

## Final local acceptance — 2026-10-16

All **41/41 ordered live steps passed**, finishing at 16:04:33 UTC (18:04:33 Amsterdam). The exact ordered command contract, current input digest, original cluster identity and final run identity were checked after completion.

| Field | Recorded value |
| --- | --- |
| Proof | `209adbc4-ca55-41ae-9b6a-168dce3f8db8` |
| Input digest | `3155a2cc2cc3eb93f679ce660a3179ff8a27fbea99575d313f90a55b5cc3667c` |
| Original cluster UID | `bef1f3e7-a9c6-43bb-9847-a0ee756cd38c` |
| Final provision/publication run | `5c3caf5c-6263-4b01-ba73-b4f678348f77` |
| Receipt | `.build/proof-manifest.json` |
| Private per-step logs | `.cache/proofs/209adbc4-ca55-41ae-9b6a-168dce3f8db8/00.log` through `40.log` |

Acceptance includes 18 static checks, 41 offline regressions (25 Python, 11 UI/HTTPS, five collector), UI type-check/lint, credential expiry/repair, same-CA certificate renewal, 18 PKI/Transit checks, ten observer RBAC checks, destructive-plan refusal, scoped snapshots and collector upgrade/rollback/re-upgrade. Two initial lab passes and a final post-cold-start lab passed their idempotency gates. Standalone drift, stack verification (23 checks), token boundaries (19 checks) and identity checks passed.

The standard browser suite passed **130/130**, plus one separate live leader-failover journey. All nine scenarios passed, each followed by full stack verification, including all four scenario-08 drift mutations and the existing CRC VM cold start. The two screenshot journeys produced 26 captures. Visual review inspected runtime-source disclosure on desktop/mobile, engines on mobile, help on desktop/mobile and the desktop audit table. Wrapping, source labels, ownership/runbook links and the retained table scroll region were checked alongside automated axe/containment checks. This review is not a claim of exhaustive assistive-technology testing.

Final dependency inventory passed with **zero mutable references in active pods and current workload templates**. Four mutable historical references remain recorded in completed Job pods; the earlier targeted inventory recorded six. Historical objects were not rewritten or manually deleted. Installed VSO remains `vault-secrets-operator.v1.6.1` with Manual approval. No operator version upgrade was performed.

After acceptance, `crc status` reported both CRC and OpenShift Running, and the original cluster UID was independently confirmed. No reset or data restore occurred. Runtime selection was preserved with `ALLOW_PODMAN=1` throughout.

### Limits retained

- M06 isolated restore, external encrypted backup custody and persistent-data recovery remain owner-deferred. The two private snapshots record `restoreProven=false`. S05 acceptance covers the documented stateless collector configuration rollback and audit recovery only.
- The receipt records `dirty=true`: this is source-bound local acceptance, not a clean-revision protected release receipt. Protected live CI remains unexecuted; no commit, push, tag or release was made.
- The host uses Node 25.2.1, outside the UI package's supported engine range. These local checks document that observed environment; they do not extend support. Build/production use pinned Node 24, and protected CI must use its declared supported runtime.
- VSO status/readiness observations do not correlate an operator rotation receipt with delivered secret content. The UI continues to report accepted-unverified where appropriate.
- The audit buffer remains volatile; this increment does not provide durable audit retention.
