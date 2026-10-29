# Rotation add-on — assessment (prompt 01_01)

Date: 2026-10-28. Working document for the rotation prompt set; not user docs.
All probes were read-only. Tokens were read from `.secrets/tokens/` by a
scratch script and never printed.

## Baseline

`make verify` reported 22 ✓ and 1 ✗. The failure was "Convergence: stale run",
caused by the same day's `make up` fixes (`scripts/down.sh`,
`terraform/seal`, `sg_seal_agent`) changing the input digest. `make lab` was
run to refresh the stamp; see the execution log in `STATE.md`.

## Facts from 00_01 §5

| Fact | Result |
| --- | --- |
| `tf-run.sh` injects a token only for `seal` and `platform`; `init -lockfile=readonly`; interactive `destroy` | confirmed |
| `make help` reads `$(MAKEFILE_LIST)` | confirmed (`Makefile:9-10`) |
| The secret scan walks KV **data** only | confirmed (`scripts/scan-secrets.py:79-99`) |
| `sg-tf-platform`: ACL policies yes, EGP no | confirmed live (P1) |
| `sg-ansible-platform`: identity groups, k8s auth roles, KV data | confirmed live. **Changed:** KV *metadata* is read/list only (P2) |
| Licence: Sentinel, Control Groups | confirmed (`.build/terraform/platform.json`) |
| `vault events subscribe` in the Vault image | confirmed (`oc exec vault-0`) |
| Collector shape and ingress | confirmed live, with more fields than recorded (P7) |
| Vault ingress allow-list | confirmed: one per-pod policy, `vault-ingress` (P9) |
| Collector code pattern (D15) | confirmed |

No fact is *false*.

## Probes

| # | Result | Evidence |
| --- | --- | --- |
| P1 | `sg-tf-platform` on `shift-gear/sys/policies/acl/sg-rotation-controller`: create/read/update/delete/list. On `shift-gear/sys/policies/egp/sg-rotation-kv`: **deny** | `sys/capabilities-self` from the root namespace. Inside the namespace the call is refused; the tool tokens are root-namespace tokens, so paths take the `shift-gear/` prefix. |
| P2 | `sg-ansible-platform`: `auth/kubernetes/role/sg-rotation-controller` full; `identity/group` create/update; `kv/data/shift-gear/rotation/*` create/read/update; `kv/metadata/shift-gear/rotation/*` **read/list only**; `kv/config` deny; `sys/events/subscribe/*` deny | same |
| P3 | Groups are per auth mount: `oidc-`, `ldap-`, `jwt-` × `operators`, `auditors`, `engineers`, `approvers` (12 groups) | `LIST identity/group/name` |
| P4 | Documented: members of a subgroup inherit the parent group's policies. **Not documented:** an *external* group as a member of an *internal* group. 01_04 must prove it live. | developer.hashicorp.com/vault/docs/concepts/identity: "the members of GroupB will have access to policies on both GroupA and GroupB" |
| P5 | `kv` is KV v2 (`options.version = 2`). Mount-level `max_versions` and `cas_required` cannot be read with tool tokens. Per-secret metadata sets both, which is the design anyway. | `sys/mounts/kv` (tf-platform) |
| P6 | Event types include `kv-v2/data-write`, `data-patch`, `metadata-write`, `metadata-patch`. Subscribing needs `read` on `sys/events/subscribe/<type>`, plus `list` and `subscribe` with `subscribe_event_types` on the secret paths. The event JSON carries `data.event.metadata.path` and `data_path`. GA and enabled by default since 1.16; Enterprise. Namespaced subscription is **not covered** by that page, so 01_03/01_04 prove it live with the controller's own token. | developer.hashicorp.com/vault/docs/concepts/events |
| P7 | `GET /audit` entries: `id, time, type (request\|response), operation, namespace ("shift-gear/"), path ("kv/data/shift-gear/…"), displayName, policies, error, hmacFields`. The collector reports `dropped`, `received`, `startedAt`, `lastEntryAt`. Every operation appears twice (request + response): count `type=request`, deduplicate on `id`. Example display names: `token-ansible-platform`, `shift-gear-auth-kubernetes-sg-workloads-vso-workloads`. | `oc exec deploy/sg-ui -- node -e fetch(...)` (shape only) |
| P8 | `registry.access.redhat.com/ubi9/python-312-minimal`, arm64 digest **`sha256:6e8175c7a7d288ebeddd1b929def954e6d9e46a533a21641e6eae562b3c9a081`**; user 1001, Python 3.12, about 64 MB | `oc image info --filter-by-os=linux/arm64` |
| P9 | `sg-vault/vault-ingress` and `sg-app/sg-audit-ingress` are per-pod ingress allow-lists with no default-deny. Additive policies selecting the same pods add allowed sources. | `oc get netpol` |
| P10 | Node requests: CPU 3681m (47%), memory 12300Mi (52%). The add-on budget (≤ 100m CPU, ≤ 256 Mi limits) fits easily. | `oc describe node` |
| P11 | The licence has Sentinel. EGPs live at `sys/policies/egp/<name>` (`paths`, `enforcement_level`) and apply to every token except root. `sg-tf-platform` needs the narrow bootstrap grant (01_07, D18). | P1 + licence features |
| P12 | `down.sh` scales `--all` only in `sg-app`, `sg-workloads` and `sg-identity` (`:38`, `:91-99`). `sg-rotation` is not touched, so the planned hook is needed. No label-wide deletes. | grep `scripts/` |

## Design adjustments (binding for 01_02+)

1. **CLI rotation requests** cannot use the Ansible token, because it only
   reads metadata. The add-on root creates token role **`sg-rotation-cli`**,
   which may only issue `sg-rotation-operator` (TTL 5m, no default policy,
   orphan). The CLI mints a token from it with the Ansible token, which the
   bootstrap policy allows: `shift-gear/auth/token/create/sg-*`. The token
   is used for the one patch and then revoked.
2. **Operator groups:** the internal groups `sg-rotation-operators` and
   `sg-rotation-auditors` take the three mount-specific external groups as
   members (`oidc-*`, `ldap-*`, `jwt-*`).
3. **Usage counting:** count `type=request`, `operation=read`,
   `namespace=shift-gear/`, `path=kv/data/<prefix>/<type>/<name>`, no
   `error`, deduplicated on `id`. Exclude the controller's own
   `displayName` (`shift-gear-auth-kubernetes-sg-rotation-…`, confirmed in
   01_04).

## Fallbacks chosen

| Risk | Fallback |
| --- | --- |
| P4: an external group cannot be a member of an internal group | Attach `sg-rotation-operator` and `sg-rotation-auditor` directly to the `*-operators` and `*-auditors` external groups in `ansible/roles/sg_identity` vars. Core touch, recorded in D17. Vault accepts policy names that do not exist yet. |
| P6: namespaced event subscription refused | Event triggers run from the 10 s metadata poll. `/status` reports `events: polling`. Human requests are unaffected. |
| P7: collector shape changes | Usage becomes "not available" in status and compliance (honest), and moves to Should. |
| P8 | Not needed: the image exists for arm64. |

## Go / no-go

| Prompt | Verdict |
| --- | --- |
| 01_02 controller + CLI | **go** |
| 01_03 terraform root | **go** (+ token role `sg-rotation-cli`) |
| 01_04 ansible + lifecycle | **go**: prove P4 and P6 live first |
| 01_05 rotation-test | **go** |
| 01_06 UI | **go** |
| 01_07 Sentinel | **go**, with the narrow bootstrap-policy grant (D18) |
