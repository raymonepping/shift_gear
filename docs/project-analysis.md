# Shift Gear — project analysis

Review date: 2026-10-14. Scope: the current working tree, including the existing uncommitted corrections and article version 06. This is a source, documentation, screenshot and saved-evidence review. No cluster was started, stopped, reset or changed for this review. Historical passing results below are dated evidence, not a claim about today's running cluster.

Related documents: [MoSCoW roadmap](roadmap.md), [project/product requirements](PRD.md), [architecture](architecture.md), [operations](operations.md), [security model](security-model.md), [frontend design](frontend/DESIGN.md).

## 1. Assessment

Shift Gear already has the right architectural foundations for a serious reference implementation: an explicit Terraform/Ansible ownership rule, a single interleaved phase list, scoped Vault tokens, a transit seal through an authenticating agent, VSO delivery, secret scanning, repeat-run checks and real disruption scenarios. The strongest next investment is to make its observations and actions as dependable as its provisioning model.

The priority is to close a few source-confirmed gaps, then extend recoverability and component depth. A new visual identity, a generic Vault administration console or a rewrite of the five Terraform roots would create more surface area before those improvements have been proved.

The highest-priority security finding is an exception to the intended value/state boundary: the local foundation Terraform state contains a nonempty controller-generated token-reviewer JWT. The check reported field names and presence only, never the token. Product gaps are also visible in source contracts: an offered re-injection action has no endpoint; rotation confirmation polls a host-published snapshot; some missing observations receive a new timestamp; role-visibility tests use selectors absent from the buttons. The historical suite can be green while these behaviors remain unproved. None of this invalidates the recorded clean-build and failover results; it limits what those results establish.

## 2. Architecture and ownership inventory

| Component | Current responsibility | Strength to preserve | Extension opportunity |
| --- | --- | --- | --- |
| `terraform/infra` | Discovers ingress domain and first pod CIDR, publishes six-field contract and ingress CA file | Platform consumers obtain connection data through one boundary | Validate schema, capabilities, multiple CIDRs, registry/storage assumptions and cluster identity |
| `terraform/foundation` | Namespaces, accounts, RBAC, selecting NetworkPolicies, Vault Routes, build resources, VSO subscription | Cluster structure is declarative | Named capability contract; non-CRC profile; controlled operator upgrades |
| `terraform/workloads` | Helm releases, seal agent/rotator, identity/database/demo deployments, VSO CRs, console and collector | Field-specific exceptions preserve runtime reconciliation | Smaller internal organization without changing resource addresses; meaningful lifecycle tests |
| `terraform/seal` | Transit mount/key, AppRole roles and policies | Non-exportable key, deletion guards, separate credential issuer | Seal dependency restore, rotator recovery and audit evidence |
| `terraform/platform` | Enterprise namespace, KV/Transit/PKI/DB mounts, policies, token role, two audit devices | Structure is separate from secret values | End-to-end PKI/Transit proofs, destructive-change protections and recovery coverage |
| Eight Ansible phases | Preparation, initialization, issuance, federation, auth/config, seeds, UX publication, validation | Explicit order and observed reconciliation | Check-mode coverage map, precise change exceptions, bounded diagnostics |
| `scripts/phases.txt` and wrappers | Thirteen phases, three automatic gates, command-specific environment | One authoritative phase order | Run identity, lock, failure record, portable digest, publish transaction |
| Vault seal chain | Seal Vault → AppRole Agent proxy → three main Raft members | Main Vault pods hold no usable seal token; mTLS to proxy | Recovery across both Vault stores and credential expiry |
| VSO | Kubernetes auth; KV and DB credentials into destination Secrets; workload restarts | Apps do not need Vault tokens | Operation acknowledgement through observed sync and consumer readiness |
| Nuxt 4 BFF/UI | OIDC login, server-side Vault session, read-only evidence plus a scoped KV rotation action | Browser receives an opaque session cookie rather than the Vault token | Honest source/freshness states, action completion, session semantics |
| Audit collector | TCP ingestion; projected metadata in a 1,000-entry memory buffer; HTTP read API | Values discarded, bounded entry count, independent stdout audit device | Stream bounds, restart identity, browsing, access review and durable export option |

The five namespaces are `sg-vault-seal`, `sg-vault`, `sg-identity`, `sg-workloads`, and `sg-app`. CRC is a single-node environment: three Vault pods do not provide three host failure domains. The seal Vault is a single Raft-backed instance with a Shamir 1-of-1 seal. Keycloak uses the development database on a PVC; LDAP is a single instance. These are deliberate lab constraints and must stay distinct from a future deployment profile.

### Phase order

```text
Terraform infra → foundation
Ansible prepare
Terraform workloads
Ansible seal-init
Terraform seal
Ansible agent → bootstrap
Terraform platform
Ansible identity → configure → ux → validate
Gates: idempotency → Terraform drift → secret scan
```

`make boundary`, standalone full `make drift`, identity verification, browser checks and resilience scenarios are additional proofs. Four gate cards in the UI include the validation phase; that does not mean `make lab` has four automatic trailing gates.

### Ownership invariants

- Terraform owns structural resources and policy definitions. Keeping secret values out of state is the intended invariant; F22 identifies a confirmed token-reviewer exception that must be corrected.
- Ansible owns initialization, ordered configuration, credential issuance, secret values and evidence publication.
- VSO owns runtime Secret synchronization and its narrowly named workload-restart annotations.
- The console observes automation; it does not execute Terraform, Ansible or arbitrary cluster commands.
- The existing operator rotation is a bounded application action using the visitor's own Vault token. This must be described accurately rather than calling the entire console observe-only.
- Kubernetes administrator credentials and retained Vault root tokens remain more privileged than the four normal tool tokens. The token boundary constrains routine operations; it does not eliminate bootstrap authority.

## 3. Evidence baseline and confidence

| Saved proof | Result | Evidence and qualification |
| --- | --- | --- |
| Fresh CRC plus lab, 2026-10-10 | 13m17s wall time | Cached bundle and local prerequisites retained; a replacement VM and generated lab state |
| Fresh `make lab` | 9m00s recorded; 9m59s command wall time | `.cache/convergence-from-nothing.json`; final evidence republish follows recorded total |
| Independent second lab | 5m11s recorded | `.build/convergence.json` at time of proof; all five Terraform plans empty |
| Ansible repeat run | Enforced phases `changed=0` | UX evidence publication is the documented phase exception |
| Static checks | 18/18 | `.cache/review-2026-10-09/check-post-docs.log` |
| Stack verification / boundary | 22/22 and 19/19 | Saved `verify-post-rebuild.log` and `boundary-post-rebuild.log` |
| Standard Playwright | 104 passed | Saved `ui-test-post-rebuild.log`; desktop/mobile Chromium with TLS verification |
| Scenarios 01–09 | All recorded passing | Active deletion, Agent restart, rotation, seal restart, cold start, VSO rotations, drift and hand-edit repair |
| UI failover | Separate pass, 2.3 minutes | Live leader change plus republished snapshot and recovered browser view |
| Screenshots | 22 captured | Historical images, not fresh rendering; four inspected in this review |

The first fresh rebuild failed on the seal agent's Ansible-owned rotation annotation. A scoped Terraform exception corrected field ownership, and the successful proof started from a second reset. Keep both records. The project has evidence of a genuine corrected bootstrap, not only a resumed partial apply.

The local `.cache/`, `.build/`, and `prompts/` evidence is ignored by Git. The tracked repository needs a sanitized proof manifest for durable review and release traceability. Do not commit raw logs, snapshots or secret-bearing archives to solve that problem.

## 4. Findings and strengthening opportunities

Labels below distinguish **confirmed source behavior**, **historical visual evidence**, and **unproved capability**. Priority means the next strengthening release, not an assertion that the existing lab is unusable. IDs map to the roadmap and PRD.

### F01 — Observation freshness is not a common contract

**Confirmed source behavior. Must, M01.** [Evidence reader](../ui/server/utils/evidence.ts) parses JSON without runtime schema validation. [Fleet](../ui/server/api/v1/fleet.get.ts), [Cluster](../ui/server/api/v1/cluster.get.ts), Agent and other readers fall back to the request's current time when the evidence timestamp is absent. Fleet's equality comparisons can also treat missing numerator/denominator values as equal. [useFleet](../ui/app/composables/useFleet.ts) can retain a healthy seal-chain label from old data after refresh failure.

Introduce explicit source, observation time, retrieval time, age, validity and availability. Missing data must be unknown, malformed data invalid, and old healthy observations stale. Reloading an old ConfigMap must never count as a new observation. TTLs cannot be interpreted as current without their observation time.

### F02 — Rotation acknowledgement and completion are disconnected

**Confirmed source behavior. Must, M02.** [Operator UI](../ui/app/pages/operator.vue) writes through a real [rotation endpoint](../ui/server/api/v1/operator/static-secrets/[name]/rotate.post.ts), then polls `lastSyncTime` from [snapshot-based status](../ui/server/api/v1/operator/secrets.get.ts). Polling the same snapshot cannot establish the operation's effect. A changed timestamp alone also does not correlate the Secret to the just-written KV version.

Separate write accepted, VSO synced and consumer ready. A bounded observer should correlate metadata to the returned version or safe operation marker without returning secret bytes. While that observer is unavailable, report accepted but unverified, with a host-side verification path. Add KV v2 compare-and-set and a defined retry/idempotency strategy; the current read/merge/write sequence can overwrite a concurrent writer's changes.

### F03 — Re-injection is an offered but unsupported action

**Confirmed source behavior. Must, M02.** [Agent UI](../ui/app/pages/agent.vue) calls `/api/v1/agent/{name}/reinject`; the server tree has status only. Errors go to `console.error`, not to an accessible user-visible result. First disable the control with an explanation and host guidance. Implementing it later requires an explicit ownership decision and narrow service account; do not add broad pod-delete rights to the BFF as a shortcut.

### F04 — Some role tests can pass without testing their claim

**Confirmed source behavior. Must, M05.** [Agent tests](../ui/tests/agent.spec.ts) and [Operator tests](../ui/tests/operator.spec.ts) assert absence of `data-testid` selectors not present on the actual buttons. They do not prove that an authorized operator can execute the action. Strengthen tests around accessible names, exact authorized visibility, direct HTTP authorization denials and completed or honestly incomplete effects.

### F05 — Backchannel logout is an acknowledgement, not session invalidation

**Confirmed source behavior. Must, M03.** [Receiver](../ui/server/routes/auth/kc-backchannel-logout.post.ts) returns success without validating a logout token or locating sessions. The [session model](../ui/server/utils/session.ts) has no issuer/subject/session-ID mapping. Initiating application logout destroys the local session, but that is a different behavior from reacting to provider-initiated logout.

Make the distinction explicit. Design a validated, replay-resistant identity-to-session mapping compatible with Vault's OIDC mediation, or stop advertising a functional backchannel receiver until that integration exists. Reject malformed callbacks and preserve the tested Ada → sign out → Ben journey. Backchannel token validation and session matching are specified by [OpenID Connect](https://openid.net/specs/openid-connect-backchannel-1_0.html).

### F06 — BFF session and mutation hardening needs negative proofs

**Confirmed source behavior; threat impact not penetration-tested. Must, M03.** Sessions use process memory; expired entries are removed when accessed. Pod replacement loses sessions, replicas would not share them, and active policy claims remain a login-time snapshot. Secure-cookie selection trusts forwarded protocol. No explicit mutation Origin/CSRF check or rate limit appears in the inspected routes; SameSite cookies are a partial defense, not a complete action policy.

Define the single-replica fail-closed contract, expiry cleanup, trusted proxy boundary, logout/revocation outcomes and forged cross-origin request rejection. A shared session store is a later scaling decision, not an automatic requirement. Never log raw session objects or silently fall back to an elevated Vault token.

### F07 — Evidence can describe different runs as one result

**Confirmed source behavior. Must, M04.** [lab.sh](../scripts/lab.sh) records success before the final UX publication. A later failed run can leave an earlier convergence file. Gates and run records lack one common cluster/run identity. Concurrent `lab`, `drift`, `ux` and scenarios can overwrite shared artifacts. Missing required phase files currently terminate the lab with exit 0.

Add a shared mutation lock, unique run IDs, cluster binding, phase/gate completion status and distinct provisioned/published outcomes. Missing required phases must fail. Preserve the last successful record separately from the latest attempted run. Failed publication must not masquerade as either a fresh displayed success or a failed infrastructure apply with no explanation.

### F08 — The automation digest is incomplete and location-dependent

**Confirmed source behavior. Must, M04.** [automation-digest.sh](../scripts/automation-digest.sh) hashes `shasum` output containing absolute file paths. Moving the checkout can change the digest. Scripts other than `phases.txt`, the callback Python, the collector, UI sources and provider locks are not all in its input contract. A reader can interpret matching hashes as stronger freshness than the digest supports.

Hash sorted repository-relative names and bytes with an explicit manifest; separate automation, UI and observation identities. Include executable and dependency inputs; exclude caches, state and secrets. Test relocation, changed scripts, changed policies and unchanged generated outputs.

### F09 — UX idempotency is allowed at phase granularity

**Confirmed source behavior. Must, M07.** [idempotency.sh](../scripts/idempotency.sh) and [drift.sh](../scripts/drift.sh) accept nonzero UX change counts based only on the phase allowlist. That can hide a future repeated image build, pod deletion or unrelated task change under the evidence exception. Ansible check mode also does not establish coverage for skipped federation or command tasks.

Identify allowed change events by stable task identity and reason. Reject extra changes. Publish coverage states such as checked, unsupported and separately verified. Ansible documents that [check-mode support depends on the task/module](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_checkmode.html).

### F10 — Provider selection and releases are not fully reproducible

**Confirmed source behavior. Should, S05; CI foundation in M05.** [Gitignore](../.gitignore) ignores `.terraform.lock.hcl`; no provider lockfiles are tracked in the inspected tree. Provider constraints permit updates, some images use mutable tags, and VSO's stable subscription has automatic install-plan approval. Existing digest pins and collection pins are valuable but do not cover the entire release.

Version the supported tool/provider/chart/operator matrix; commit reviewed lockfiles; define multi-architecture selection and controlled update procedures. Keep in-cluster builds, but record built image digest alongside source digest. A general secret-bearing Terraform resource remains stateful even if its display is marked sensitive; the structural/value boundary should remain the default. See [Terraform sensitive-data guidance](https://developer.hashicorp.com/terraform/language/manage-sensitive-data).

### F11 — CI does not enforce the local proof ladder

**Confirmed source behavior. Must, M05.** Tracked workflows are [Gitleaks](../.github/workflows/gitleaks.yml) and [release](../.github/workflows/release.yml). There is no tracked static/UI/contract-check workflow or deployment-gate workflow. [Release checklist](release-checklist.md) centers on Git/tag/release operations. Shape tests exist, but the platform test named `kv_has_prevent_destroy` checks mount path/type rather than attempted destruction.

Introduce fast PR checks and separately protected live/destructive jobs. Test actual invariants, not labels that resemble them. Design a portable runner before putting macOS-specific shell commands into Linux CI. Release evidence must carry the tested revision/digest and incomplete/skipped status.

### F12 — Reconstruction has been proved; data restoration has not

**Unproved capability. Must, M06.** There are no dedicated snapshot/restore workflows in the reviewed scripts or scenarios. Reset archives credentials and state, then destroys the live data. Neither clean re-creation nor pod/PVC survival establishes recovery of post-bootstrap secrets, PKI state or transit keys.

Design recovery for both Raft stores, retained unseal/recovery material, TLS trust, external identity and PostgreSQL dependencies. Restore the seal dependency before expecting the main cluster to decrypt. Because the seal transit key is non-exportable and deletion-protected, protecting its backing store is essential. Use an isolated target: HashiCorp's [snapshot restore procedure](https://developer.hashicorp.com/vault/docs/sysadmin/snapshots/restore) calls out isolation and restore-completion verification. This review authorizes planning, not executing a restore or reset.

### F13 — Credential and CA operations depend on the controller

**Confirmed design constraint. Must, M08; broader identity migration Could, C01.** Root tokens are retained locally, bootstrap tokens are renewed by phases, the rotator's secret-id has no expiry, and TLS material is generated by [tls.sh](../scripts/tls.sh). These choices make a local lab workable. They need explicit custody, lifetime and expiry/recovery paths before calling the platform unattended.

Inventory credentials without exposing values; provide age/expiry and renewal-failure states; prove expired IDs and tokens can be repaired by the intended role. Guard CA replacement and stage trust rotation before leaf rollout. Separate bootstrap root authority from routine scheduled observations. Review the long-lived token-reviewer Secret and unused API token role before migrating identities.

### F14 — More Vault components are declared than are exercised

**Confirmed coverage gap in reviewed scenario inventory. Should, S02.** PKI root/intermediate/role and application Transit key are provisioned. Existing scenarios concentrate on HA, auth, VSO and drift. Add certificate issue/verify/revoke/expiry and transit encrypt/decrypt/rotate/rewrap/old-ciphertext proofs with bounded policies. Keep private keys and plaintext outside Terraform state and UI responses. Validate destructive guards on actual mount/key changes, not only field values.

### F15 — Portability is a hypothesis beyond the current cluster

**Unproved capability. Should, S04.** [Infra](../terraform/infra/main.tf) discovers the first pod CIDR and uses a fixed registry address; [Vault values](../deploy/vault/values.yaml) clear anti-affinity for CRC. Image build staging invokes `xattr`, and lifecycle paths explicitly call CRC helpers. Documentation in [substrate contract](substrate-contract.md) and [enterprise mapping](enterprise.md) makes stronger universal claims than the saved runs establish.

Build a capability preflight and a second OpenShift profile. Keep schema evolution backwards-compatible and distinguish platform automation from host lifecycle. Test storage class, registry, trust, architecture, multiple CIDRs and failure domains. Do not split all roots into modules before that evidence identifies reusable boundaries.

### F16 — Visual system is cohesive; mobile containment is unproved

**Historical visual evidence plus source support. Must, M01; deeper design work Should, S06.** Desktop Fleet/Cluster captures show a consistent pale-glass shell, dark hero and readable provenance. The inspected [Operator mobile capture](screenshots/ui/operator-mobile.png) is 604 pixels wide although [screens.spec.ts](../ui/tests/screens.spec.ts) requests 390. Navigation extends beyond the shell; [AppShell](../ui/app/components/AppShell.vue) uses a nonwrapping flex row without a contained mobile overflow pattern. Reproduce on a new run before asserting today's pixels, then fix and test document width.

The [Audit mobile capture](screenshots/ui/audit-mobile.png) is 42,301 pixels tall. Add paging or bounded rendering, scoped table scrolling and keyboard-visible controls. Screenshot creation and axe scans do not alone establish navigability, workflow completion or absence of document overflow.

### F17 — UI copy overstates some operational knowledge

**Confirmed source behavior. Must, M01/M02; Should, S06.** Shell/footer copy says actions run from the host while Operator implements a Vault write. Snapshot refresh buttons imply checking, Fleet says “no token” when token TTL is unreported, and some audit copy asserts that stdout is working without observing that device at request time. The design spec also still describes unimplemented filters/raw JSON and a live Cluster refresh model.

Use data-aware descriptions: “reload published evidence,” “token TTL not reported,” “last verified stdout device,” and “rotation requested; sync not yet observed.” Preserve concise product language and move command/source details into an optional evidence drawer. This improves decisions without turning each screen into an implementation manual.

### F18 — Audit metadata access and stream robustness deserve explicit policy

**Confirmed source behavior. Must, M03/M05; Should, S06.** Every signed-in user can read projected metadata through the BFF. The collector's entry count is bounded, but `MAX_LINE` is checked after complete lines are processed; an oversized newline-terminated record is not rejected by that check. IDs restart at one on collector restart. No dedicated collector behavior tests are in the inspected test inventory.

Review access as a product decision, test an allowlist projection and metadata filtering, bound lines before parsing, and give each collector instance an identity. HMAC protection is not anonymity. Keep the independent audit device; a durable sink is an optional integration, not another in-memory buffer with a stronger label.

### F19 — Lifecycle diagnostics can report success after suppressed errors

**Confirmed source behavior. Must, M04/M08.** [down.sh](../scripts/down.sh) suppresses scale/delete errors, and reset moves local state before deletion is confirmed. The strengthened `up` waits and verifies, but down/reset can still claim completion after partial failure. The `crc status` incident in this session also demonstrated that a running hypervisor and an available API are different states.

Use bounded preflight/status checks, identity-bound destructive confirmation, verified postconditions and partial-failure records. Do not take destructive action based on a stale PID alone. Host helper setup, VM state, API state, Vault seal state and workload readiness must be independently visible. Preserve the operator's chosen runtime; tests must not silently change the final host state.

### F20 — Secret scan coverage is best-effort and artifact-sensitive

**Confirmed source behavior. Must, M05.** [secret-scan.sh](../scripts/secret-scan.sh) scans tracked files, state, `.build/`, and top-level cached logs. Known-value reads suppress source errors; KV listing excludes nested directories; nested review logs and untracked sources are not comprehensively covered by the default file selection. File-content matching also cannot prove that argv, process memory or external logs never saw a secret.

Report coverage by required source and target scope, recurse through intended KV metadata paths, scan staged/untracked delivery candidates, and treat required-source failure as incomplete. Add synthetic leak canaries under test-controlled paths and verify that only filenames/labels are emitted. Restrict permissions and retention for secret-bearing backup material separately from public proof artifacts.

### F21 — Approver/admin presentation disagrees with mutation authorization

**Confirmed source behavior. Must, M02/M03/M05.** [Session response](../ui/server/api/session.get.ts) marks either `sg-operator` or `sg-approver` as `isAdmin`. Operator/Agent pages offer controls for that flag, while the rotation endpoint accepts only `sg-operator` or `root`. The approver can therefore be offered an action the server denies. Define capabilities explicitly, reconcile UI/API permission matrices and test Dirk as well as Cleo/Ben. Do not broaden Vault policy merely to make the label true.

### F22 — A controller-generated reviewer JWT is stored in Terraform state

**Confirmed source and local-state presence. Must, M08/M07/M05; first remediation priority.** [Foundation](../terraform/foundation/main.tf), resource `kubernetes_secret.vault_token_reviewer`, creates a `kubernetes.io/service-account-token` Secret and waits for the controller to populate it. The comment says the token is never set in state, but the local `.secrets/terraform/foundation/terraform.tfstate` resource data includes the `token` key with a nonempty value. This review queried only keys and a boolean presence check; no credential content was emitted. Provider refresh can persist a computed secret even when HCL never sets the value.

Move reviewer-token value lifecycle outside Terraform's ordinary state resources, or adopt a verified projected/local-reviewer identity design. Keep Terraform ownership of required ServiceAccount/RBAC structure. Validate Kubernetes auth continuity, revoke/replace the prior token, and handle protected local state/backups/archives under a deliberate cleanup plan. Do not automatically delete historical files or rotate credentials during this documentation review. The current scanner's known-token inventory does not include this reviewer JWT and its patterns target Vault tokens rather than Kubernetes JWTs, which explains how the intended invariant can fail without a scan finding. Add structural state assertions and synthetic JWT canaries; keep affected state confidential. Update the misleading source comment and security documentation as part of the correction.

Local state presence is not evidence of external disclosure. The finding concerns credential custody and invariant coverage; it does not establish that a token was published or used improperly.

## 5. Recommended investment order

1. Correct the reviewer-token state exception in M08/M07 and add the M05 detection guard before further state distribution or release. Close observable product gaps M01–M03 with targeted negative tests alongside them.
2. Make each proof belong to one run: M04, M07 and M05 release manifests.
3. Establish data-preserving recovery and lifecycle custody: M06 and M08.
4. Exercise deeper Vault capabilities and bounded runtime observation: S01–S03.
5. Prove a second cluster/profile and a controlled update: S04–S05.
6. Extend investigation UX and optional integrations after the core evidence is dependable: S06 and Could items.

Work may overlap by dependency, but live mutations remain serialized. The [roadmap](roadmap.md) defines outputs and exit gates; the [PRD](PRD.md) defines measurable behavior. No calendar estimate is asserted without an assigned team and environment.

## 6. Review limits

No new live convergence, browser run, penetration test, external-cluster deployment or restore was performed. Four historical screenshots were inspected; this is not a fresh visual pass over every screen. Existing dependencies and policies were reviewed at their checked-in/current working-tree versions. Local verification during this review passed four `sg_stats` callback unit tests, recursive Terraform formatting and `git diff --check`; these do not substitute for a full static/live baseline. Official references were checked for the design proposals, not used as evidence that this repository implements those proposals. Cluster connectivity, licence validity and host runtime status must be re-established by the implementation baseline before a code-changing milestone.
