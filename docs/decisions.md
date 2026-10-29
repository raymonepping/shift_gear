# Decisions

Non-obvious architectural choices, each with the evidence that motivated it.

---

## D01 — Substrate contract: discover, not hard-code

**Question:** Should `apps_domain` be a variable in `terraform.tfvars` or discovered from the
cluster?

**Run:** `oc get ingresses.config.openshift.io/cluster -o jsonpath='{.spec.domain}'`
→ `apps-crc.testing`

**Decision:** Discover it from the cluster using a `kubernetes_resource` data source in
`terraform/infra/`. The same data source works on any OCP cluster because
`ingresses.config.openshift.io/cluster` is a standard OpenShift resource. A hard-coded variable
would break when the domain changes and would need manual updating per substrate.

Same rationale for `pod_cidr` from `networks.config.openshift.io/cluster`.

---

## D02 — No seal token on the cluster

The transit seal in `deploy/vault/values.yaml` points to
`https://seal-agent.sg-vault-seal.svc:8200` with a project-CA client certificate.
Its placeholder token is replaced by the agent’s `api_proxy` using its own
AppRole auto-auth token. Cluster pods therefore carry no seal-Vault token.
The agent owns its short-lived in-memory token; the rotator replaces its
secret-id every six hours.

---

## D03 — Five Terraform roots

**Question:** Why five roots (`infra`, `foundation`, `workloads`, `seal`, `platform`) instead of
one or two?

**Evidence:** Each root corresponds to a distinct lifecycle and a distinct tool boundary:

| Root | Runs as | May not run as |
|---|---|---|
| `infra` | Kubernetes identity from kubeconfig | Vault token |
| `foundation` | kubeadmin | — |
| `workloads` | kubeadmin | — |
| `seal` | `sg-tf-seal` | `sg-tf-platform` |
| `platform` | `sg-tf-platform` | `sg-tf-seal` |

`seal` and `platform` run after Vault is initialised and cannot share a token without violating
least-privilege. Merging them would require a token that can both create the transit mount and
write platform policies — that token would have too many capabilities.

**Decision:** Five roots. Each has its own state file and lifecycle. Kubernetes roots use kubeconfig; seal and platform use distinct Vault bootstrap tokens.

---

## D04 — Vault bootstrap token via token role, not root

**Question:** Can Terraform mint its own bootstrap token from the root token?

**Evidence:** `golden_ticket` prompt 03 execution log: minting tokens from Terraform root
requires the root token in provider config. The root token ends up in Terraform state.

**Decision:** Ansible mints the bootstrap tokens (`sg-tf-seal`, `sg-tf-platform`) using
policy-specific token roles (`sg-tf-seal` and `sg-tf-platform`) and writes them to `.secrets/tokens/`. Terraform reads them
from disk (provider `token` = `file(.secrets/tokens/tf-seal)`). The root token never enters
Terraform state.

---

## D05 — CIDR restriction on the seal agent AppRole + sg-ui token role

**Question:** Is a NetworkPolicy sufficient to restrict the seal agent's AppRole, or should
the AppRole also be CIDR-restricted?

**Run:** `vault read auth/approle/role/sg-seal-autounseal` shows:
```json
"secret_id_bound_cidrs": ["10.217.0.0/22"]
```

**Decision:** Both. NetworkPolicy is Kubernetes-layer defence; CIDR restriction is Vault-layer
defence. The pod CIDR (`10.217.0.0/22` on CRC) is discovered from the contract — no hardcoded
value. `make boundary` checks policy capabilities on 19 paths; it does not perform a CIDR-restricted login. The
`sg-ui` token role also uses this CIDR so the sg-ui BFF pod (within the cluster) can reach Vault but
a developer's laptop cannot use the UI token for direct Vault API calls.

---

## D06 — Kubernetes `k8s_exec` for LDAP seed, not `community.general.ldap_*`

**Question:** Can Ansible use `community.general.ldap_entry` to seed the LDAP directory from
the Mac?

**Run:** `nc -z openldap.sg-identity.svc 1389 2>/dev/null` from the Mac — connection refused.
OpenLDAP is not exposed via a Route or NodePort.

**Decision:** Use `kubernetes.core.k8s_exec` to run `ldapadd` inside the OpenLDAP pod.
`community.general.ldap_*` modules require direct TCP access to port 1389 from the Ansible
controller (the Mac). That access is not available without a NodePort or Route, and exposing
LDAP externally is unnecessary for a lab. `k8s_exec` runs the command in-cluster where the port
is reachable.

---

## D07 — ConfigMap evidence path (not a PVC)

**Question:** How does the Shift Gear BFF pod read the evidence files (`layers.json`,
`validation.json`, etc.) generated on the Mac?

**Run:** `oc -n sg-app get pvc` — the sg-ui BFF pod has no PVC; it is a stateless container.
A PVC does not expose the Mac’s generated evidence to the pod. A ConfigMap
provides the required small, read-only bundle without a storage volume.

**Decision:** Ansible `ux` phase syncs the `.build/*.json` files as entries in a ConfigMap
(`sg-evidence` in `sg-app`). The ConfigMap is mounted as a volume in the sg-ui BFF pod at
`/evidence/`. On each `make ux` run, Ansible diffs the ConfigMap against the local
files and applies only the changed keys.

---

## D08 — No `VAULT_NAMESPACE` in environment

**Question:** Can `tf-run.sh` set `VAULT_NAMESPACE=shift-gear` to avoid repeating the
namespace in every Terraform resource?

**Run:** During `terraform/seal` apply (which targets the seal Vault, not the platform namespace):
setting `VAULT_NAMESPACE=shift-gear` caused every `vault_*` resource in `seal/` to look for
paths under `shift-gear/` on the seal Vault — which does not have that namespace.

**Decision:** `tf-run.sh` explicitly unsets `VAULT_NAMESPACE`. Each Terraform provider block
and each `vault_namespace` resource sets the namespace explicitly. Ansible tasks set
`X-Vault-Namespace: shift-gear` on individual URI calls.

---

## D09 — `notBefore = -1h` in TLS certs

**Question:** Why does `scripts/tls.sh` use `-not_before -1h` when generating TLS certificates?

**Evidence:** After a Mac sleep, the CRC VM clock can drift behind by 30–90 seconds. A
certificate issued at `T=0` with `notBefore = T` is rejected by a node that thinks it is `T-30s`.

**Decision:** Set `notBefore = now - 1h` so that certs are valid 1 hour before their issuance
time. This absorbs reasonable clock drift without materially weakening security (the cert is
issued leaf certificates last 365 days).

---

## D10 — `serverAuth + clientAuth` EKU on Vault pod certs

**Question:** Why do the Vault pod TLS certificates have both `serverAuth` and `clientAuth`
extended key usages?

**Evidence:** The seal agent's mTLS listener requires client certificates. Vault pods present
their own certificate as a client certificate when connecting to the seal agent. If the cert has
only `serverAuth`, the mTLS handshake fails with `tls: client certificate's Key Usage doesn't
allow digital signature`.

**Decision:** All Vault pod certs are generated with `extendedKeyUsage = serverAuth, clientAuth`.

---

## D11 — VSO CSV gate in `ansible prepare`

**Question:** Can `terraform workloads` apply `VaultConnection` and `VaultAuth` CRDs before
the VSO CSV is in `Succeeded` phase?

**Run:** Applied `VaultConnection` while CSV was in `Installing` phase.
Result: `no kind "VaultConnection" is registered for version "secrets.hashicorp.com/v1beta1"`.

**Decision:** `ansible prepare` polls the VSO CSV every 30 seconds for up to 10 minutes. Only
when `status.phase == Succeeded` does it allow the phase to complete, unblocking
`tf workloads`. This is enforced in `sg_prepare` with a `fail` module if the timeout is
exceeded.

---

## D12 — Keycloak `givenName` mapper (not `cn`)

**Question:** What LDAP attribute maps to the Keycloak `firstName` claim?

**Evidence:** In the `red_doors` build log: Keycloak's default `firstName` LDAP mapper uses
`cn` (common name). For users like `ada lovelace`, `cn` is the full name. The OIDC
`given_name` claim in the JWT was `ada lovelace` instead of `ada`, causing Vault's `bound_claims`
check on `given_name` to fail.

**Decision:** Map `firstName` from `givenName` LDAP attribute (not `cn`). Set `multivalued: true`
on the groups mapper. These are set explicitly in `ansible/roles/sg_identity/tasks/keycloak.yml`.

---

## D13 — Raft backend, not Consul

**Question:** Why does the Vault cluster use Raft (Integrated Storage) and not Consul?

**Evidence:** Consul requires a separate Consul cluster for HA. Running a second Consul Helm
release on CRC would add ~4 GB RAM. The Vault Raft backend has been production-grade since
Vault 1.4 and is HashiCorp's recommended storage backend for Vault Enterprise on Kubernetes.

**Decision:** Raft (Integrated Storage) on all three Vault nodes. Each node has a PVC.
On `make reset`, the PVCs are deleted so a clean re-init is possible.

---

## D14 — LDAP federation skipped in Ansible check mode

**Question:** `ansible --check` fails on Keycloak federation tasks with `check mode not supported`.

**Decision:** Federation tasks use `when: not ansible_check_mode`, so dry-run
passes skip them. Real reconciliation and the repeated real-run idempotency
gate exercise them. This skip is not an exemption for identity in
`scripts/idempotency-allow.txt`.

## D15 — Terraform owns the audit collector and both devices

`terraform/workloads/main.tf` mounts the dependency-free Node program from a
ConfigMap on a pinned UBI image. A source checksum rolls `sg-audit`; no builder
is needed. `terraform/platform/main.tf` enables stdout and socket devices.
The workloads rollout precedes the socket device, whose precondition requires
the collector output. Stdout remains enabled while the collector restarts.

## D16 — Keycloak root opens the application sign-in page

An HAProxy sidecar redirects only the exact root path to
`https://shiftgear.<apps_domain>/signin`. Other paths pass through to Keycloak
with backend certificate verification. The Route stays reencrypt and its
Service targets proxy port 8444. `KC_HOSTNAME_ADMIN` is absent; changing the
admin hostname did not implement the requested landing page and broke startup.

## D17 — The rotation add-on: KV v2 value rotation as a removable sixth Terraform root

**Question:** How does Shift Gear gain automated, observable KV v2 secret
rotation (per-type schedules; time, usage and event triggers; enforcement;
compliance reporting) without changing the core lab, its 13 phases or its
tool boundary, and so that it can be removed again?

**Evidence:** KV v2 versions secrets but does not rotate them. The core
phase list, the convergence digest, `make boundary` (19 rows) and the
idempotency exceptions are fixed contracts (`scripts/phases.txt`,
`scripts/input-digest.py`, `scripts/boundary-check.sh`,
`tests/test_must_contracts.py`). Live probes on 2026-10-28
(`addons/rotation/ASSESSMENT.md`): `sg-tf-platform` may write `sg-rotation-*`
ACL policies but no Sentinel EGP; `sg-ansible-platform` may write the
Kubernetes auth role, identity groups and KV data, but only read KV
metadata; the audit collector exposes `id`, `time`, `type`, `operation`,
`namespace`, `path`, `displayName` per entry; per-pod ingress policies in
`sg-vault` and `sg-app` accept additive allows; Vault 2.1 Enterprise ships
event notifications and Sentinel.

**Decision:** An add-on under `addons/rotation/`, outside the convergence
digest, in namespace `sg-rotation`, with its own Terraform root
(`addons/rotation/terraform`, state `.secrets/terraform/rotation/`) that is
not in `phases.txt`. It rotates **values inside Vault**, not credentials at
an issuing system. A stateless Python standard-library controller (ConfigMap
on a pinned UBI 9 Python image, the D15 pattern) with a `vault-agent`
sidecar writes new KV v2 versions with check-and-set under
`kv/shift-gear/rotation/<type>/<name>`. Vault is the only store: history is
KV v2 versions plus custom metadata (fingerprints, triggers, actors); no
database. Humans request rotations by patching custom metadata with their
own token, so Vault decides who may ask. `make rotation-down` removes the
add-on and keeps every managed secret and its history.

Core touch points are an allow-list: `Makefile` (include line, the
`rotation-proof` help text), `scripts/tf-run.sh` (the add-on root),
`scripts/check.sh` (substrate grep over `addons/*/terraform`),
`scripts/down.sh` (scale and reset hooks), `ui/**` (Engines › Rotation),
`.github/workflows/quality.yml`, `scenarios/10_kv_rotation/` and the docs.
D18 records the one bootstrap-policy change (Sentinel). `make boundary`
stays at 19 rows.

Fallbacks: if an external group cannot be a member of the add-on's
internal group, the add-on policy is attached to the `*-operators`
external groups in the core identity configuration (a core touch). If
event subscription is refused, event-driven rotation runs from a 10-second
metadata poll and is labelled "polling". A CLI rotation request (`make rotation-rotate`) goes through the
controller's loopback-only request endpoint via `oc exec`: the Ansible token
may only read KV metadata, and a root-namespace token cannot carry the
namespace's operator policy, so the operator's authority there is Kubernetes
RBAC on `pods/exec` in `sg-rotation`, and the controller records the request in
Vault with that provenance (`cli:<user> via kubernetes exec`).

## D18 — Sentinel EGP enforces KV value-rotation policy; one narrow bootstrap grant

**Question:** How is "only the rotation controller sets a managed value, and
every value meets its type's policy" enforced when broader core grants already
reach the managed prefix?

**Evidence:** `rotation-test` s06 (2026-10-28) recorded that the core policy
`sg-engineer` and the platform automation token `sg-ansible-platform` both hold
create/read/update on `kv/data/shift-gear/*`, which includes
`kv/shift-gear/rotation/**`. An ACL policy can only add capabilities; the
add-on cannot narrow a broader grant. ACL also cannot inspect a value. The
licence includes Sentinel (`.build/terraform/platform.json`). `sg-tf-platform`
had no right on `sys/policies/egp/*` (ASSESSMENT P1).

**Decision:** The add-on root manages one Endpoint Governing Policy,
`sg-rotation-kv` (hard-mandatory), on `kv/data/shift-gear/rotation/*` and
`kv/metadata/shift-gear/rotation/*`. It is rendered from `rotation.yaml`, so
schedule, generator and enforcement share one source. The EGP refuses:

- a value write that does not come from the controller. "The controller" means
  its policy *and* the Kubernetes auth token metadata of ServiceAccount
  `sg-rotation/rotation-controller`; a policy name alone could be attached
  elsewhere;
- a value write without check-and-set;
- a value outside its type's minimum length or the generator's alphabet;
- any metadata write by someone else, except a patch that touches only
  `custom_metadata.rotation_request`;
- any metadata delete.

**The core touch:** the operator approved one grant in
`policies/bootstrap/sg-tf-platform.hcl`:
`shift-gear/sys/policies/egp/sg-rotation-*` (create, read, update, delete).
The name prefix keeps every other EGP out of Terraform's reach. Bootstrap
policies are written by Ansible `bootstrap` with the root token, so the grant
lands on the next `make lab`. `make boundary` keeps its 19 rows.

**Limits:**
- Root tokens are not subject to EGPs (break-glass by design).
- Reads are not governed: engineers may still read managed values, per the
  core design.
- `make rotation-down` removes the EGP with the rest of the add-on, and with
  it the enforcement.

**Outcome (2026-10-28):** applied and live. `rotation-test` s12 shows 403 for
the platform token, an engineer, operator tampering and a too-short
controller value; a `rotation_request` patch is still allowed and rotations
continue. The capability check shows `sg-tf-platform` holds the grant only
for `shift-gear/sys/policies/egp/sg-rotation-*` (deny for other names and in
the root namespace). Two `make lab` runs converged the grant; verify,
boundary 19/19, drift, secret scan and the full UI suite (169) passed.

**D17 addendum (2026-10-28, prompt 01_09):** two more touch points, both made
general so later add-ons need no edit:
- `scripts/tf-run.sh` maps `rotation-<part>` to `addons/rotation/<part>/terraform`
  (tf-platform token, `destroy-auto` allowed);
- `scripts/down.sh` scales and resets every namespace labelled
  `shift-gear/addon`, instead of a hard-coded `sg-rotation`.

The Secure Door consumer (`sg-rotation-consumer`) has its own root and state,
and one managed secret entry (`api-key/secure-door`) in `rotation.yaml`.
