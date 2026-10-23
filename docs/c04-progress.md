# C04 delivery record

Started: 2026-10-17. Scope: policy and ownership explorer only. C01–C03 remain unselected. M06 isolated restore remains owner-deferred.

Implementation includes a versioned ownership registry, publication of the unchanged expected-capability matrix, fixed authenticated read-only API projection, source hashes and publication identity, local filters and contextual runbooks. No new Vault or Kubernetes permissions are requested. Expected declarations remain separate from live authorization results.

C04 is implemented and locally accepted; the final record below supersedes the in-progress notes. The previous Should proof `209adbc4-ca55-41ae-9b6a-168dce3f8db8` certifies the earlier input digest and does not certify C04. Initial sandboxed checks could not run the existing provider/target-lock tests; reruns with their required execution access are tracked separately. The initial attempts were not accepted as passing checks.

## Validation history

Credential-free validation passed: 18/18 static checks, 45/45 regressions (27 Python, 13 UI/HTTPS and five collector) and UI type-check/lint. These passes used the existing provider/lock tests with their required execution access; the initial restricted attempts are not counted as successful.

The initial targeted browser run was not green. C04 source equality/hashes, filters, missing/stale states and reload recovery passed, but the POST test hit the existing Origin protection (403) before method routing. It now separately asserts Origin refusal and checks the absent write route with the correct Origin. Existing runtime freshness tests also reported a large guest/host clock difference after sleep, and one session-expiry test timed out. These failures were retained; node-clock repair and an awake-held rerun were required without relaxing freshness or timeout assertions.

The Origin-correct POST probe exposed Nuxt's HTML fallback returning HTTP 200 for an unmatched API method. The explorer route now explicitly handles methods and returns 405 for writes after authentication, instead of relying on a missing route. No write capability was present. The clock helper measured and repaired a 13,626-second guest offset. A further host suspension interrupted another test run; its timeout/freshness failures remain recorded rather than weakening those checks.

The corrected build initially remained Pending because its pod could not create a Multus network sandbox (`Unauthorized`). Restarting only `openshift-multus/daemonset/multus` restored it; rollout completed and build 17 then completed. The existing UI stayed available. No reset, restore, policy expansion or runtime switch occurred.

After method-guard deployment and clock/CNI recovery, all 24 focused desktop/mobile checks passed. This includes all eight C04 browser cases, the six real runtime sources, session expiry, investigation flows and containment at 390/320/195 CSS pixels. API publication matched both source registries and exact file hashes; anonymous reads, arbitrary query input, Origin-invalid POST and Origin-correct writes were refused. Initial failed runs remain separate from this result. Full source-bound acceptance was still required at that stage.

First full acceptance failed: proof `45ef2120-1d68-4709-8e81-b89b1ac408ab`, frozen input digest `94bc847e1b19948bc395bb23a4de817767c72295cdf530b91554c86d423a8757`. Documents are outside the executable-input digest.

The first full ladder passed steps 1–15, then failed its standard browser gate: 122/138 passed, with all 16 failures identifying the same `link-in-text-block` violation in the new inline explorer link on `/help`. Functional C04 cases passed. Help/explorer links now have persistent underlines; the method-denial response also names `GET, HEAD` in its Allow header and the browser assertion requires exact HTTP 405. A fresh focused axe/API run and replacement full ladder were required.

The corrected focused axe run passed all pages as Ada at 1440px, including help and explorer. All four C04 desktop journeys passed again, including exact HTTP 405 plus `Allow: GET, HEAD`. UI type-check/lint and whitespace checks passed. The replacement full ladder then ran on frozen executable inputs.

Replacement proof `c32efda8-30e3-42e8-8c80-2a20e1f59c24`, frozen input digest `4a7228f5117702c01399232c98a72f400e9ef5a2dbd78c94854eb792d05bd18f`.

## Final local acceptance — 2026-10-17

C04 passed **41/41 ordered live steps** on unchanged executable inputs, finishing at 14:44:11 UTC (16:44:11 Amsterdam). The exact command order and successful exit status of every step, input digest, original cluster UID and final publication identity were verified after completion. Both declaration-file hashes in the final publication matched their actual source bytes.

| Field | Recorded value |
| --- | --- |
| Proof | `c32efda8-30e3-42e8-8c80-2a20e1f59c24` |
| Input digest | `4a7228f5117702c01399232c98a72f400e9ef5a2dbd78c94854eb792d05bd18f` |
| Original cluster UID | `bef1f3e7-a9c6-43bb-9847-a0ee756cd38c` |
| Final provision/publication run | `708cdedf-b958-4688-8f16-c10c4e28cb91` |
| Receipt | `.build/proof-manifest.json` |
| Private logs | `.cache/proofs/c32efda8-30e3-42e8-8c80-2a20e1f59c24/00.log` through `40.log` |

### Checks passed

- Static 18/18; offline 45/45 (27 Python, 13 UI/HTTPS, five collector); UI type-check/lint.
- Standard desktop/mobile browser suite **138/138**, including eight C04 journeys. Axe covered both personas, both widths and reduced-motion modes, with zero violations. Containment covered 390, 320 and 195 CSS pixels, retaining local table scrolling.
- Real API authentication, exact published row/hash equality, parameter rejection, Origin refusal, and explicit write refusal with HTTP 405 and `Allow: GET, HEAD`. Auditor keyboard filtering/runbook navigation, empty filters, missing/stale declarations and failed-reload recovery passed.
- Separate live leader failover; all nine existing scenarios with full verification after each; two initial labs and a final post-cold-start lab with their idempotency gates; final drift. Scenario 08 detected/repaired all four mutations. Stack verification passed 23 checks and token boundaries passed 19.
- Existing credential-expiry, certificate-renewal, 18-check component, ten-check observer RBAC, destructive-plan guard and scoped snapshot/stateless upgrade/rollback proofs.
- Two screenshot journeys generated 28 captures. Visual review inspected explorer desktop/mobile and the corrected help link on desktop: declaration labels, provenance, wrapping, persistent link cues and mobile table scrolling. This does not claim exhaustive assistive-technology coverage.
- Final inventory recorded zero mutable image references in active pods/current workload templates and three historical references in completed Job pods. No historical object was rewritten or manually deleted. VSO remains `vault-secrets-operator.v1.6.1` with Manual approval.

The authenticated console now exposes **Ownership** in navigation at `/explorer`. It shows ten ownership declarations and the unchanged 19-operation expected-capability matrix. No Vault/Kubernetes permission, user-role grant, policy editor or arbitrary path/token lookup was added. C01–C03 remain unselected; no implementation work was done for them.

After acceptance, CRC and OpenShift reported Running and the original cluster UID was independently confirmed. Runtime selection was preserved with `ALLOW_PODMAN=1`. No reset or data restore occurred.

### Limits retained

The receipt records `dirty=true`. This is source-bound local acceptance; protected live CI remains unexecuted and a clean reviewed revision is still required for release. No commit, push, tag or release was made. The host remains Node 25.2.1, outside the UI's supported engine range; local results document that observed environment and do not extend support. Build/deployed runtime use pinned Node 24.

M06 isolated persistent-data restore remains owner-deferred. Private snapshots and the existing stateless collector rollback do not close it. Explorer source hashes identify publication inputs, not review signatures or current authorization. Reloading declarations does not run live checks; the UI continues to distinguish expected access from actual capability results.
