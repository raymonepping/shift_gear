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

**Question:** Should Ansible write the unseal key to a Kubernetes Secret so that Vault pods
can unseal themselves on restart?

**Run:** Transit seal configuration in `vault/values.yaml`:
```yaml
seal:
  - type: transit
    address: "http://vault-seal-internal.sg-vault-seal.svc:8200"
    key_name: autounseal
    mount_path: transit/
```

**Decision:** No. The transit seal stanza in the Helm values handles auto-unseal without any
operator action. The cluster Vault pods contact the seal Vault directly on restart.
Writing an unseal key to a Kubernetes Secret would be a hard-coded credential in an object that
Terraform can read back (a state leak). The `golden_ticket` project proved this pattern works;
Shift Gear extends it to the OpenShift substrate.

---

## D03 — Five Terraform roots

**Question:** Why five roots (`infra`, `foundation`, `workloads`, `seal`, `platform`) instead of
one or two?

**Evidence:** Each root corresponds to a distinct lifecycle and a distinct tool boundary:

| Root | Runs as | May not run as |
|---|---|---|
| `infra` | Anonymous (read-only) | Any token |
| `foundation` | kubeadmin | — |
| `workloads` | kubeadmin | — |
| `seal` | `sg-tf-seal` | `sg-tf-platform` |
| `platform` | `sg-tf-platform` | `sg-tf-seal` |

`seal` and `platform` run after Vault is initialised and cannot share a token without violating
least-privilege. Merging them would require a token that can both create the transit mount and
write platform policies — that token would have too many capabilities.

**Decision:** Five roots. Each has its own token, its own state file, and its own lifecycle.

---

## D04 — Vault bootstrap token via token role, not root

**Question:** Can Terraform mint its own bootstrap token from the root token?

**Evidence:** `golden_ticket` prompt 03 execution log: minting tokens from Terraform root
requires the root token in provider config. The root token ends up in Terraform state.

**Decision:** Ansible mints the bootstrap tokens (`sg-tf-seal`, `sg-tf-platform`) using a
token role (`sg-token-creator`) and writes them to `.secrets/tokens/`. Terraform reads them
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
value. `make boundary` checks that a token generated outside the pod CIDR is denied. The
`sg-ui` token role also uses this CIDR so the API pod (within the cluster) can reach Vault but
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

**Question:** How does the Shift Gear API pod read the evidence files (`layers.json`,
`validation.json`, etc.) generated on the Mac?

**Run:** `oc -n sg-app get pvc` — the API pod has no PVC; it is a stateless container.
A mounted PVC would require a storage class with `ReadWriteMany`, which CRC does not provide
by default.

**Decision:** Ansible `ux` phase syncs the `.build/*.json` files as entries in a ConfigMap
(`sg-evidence` in `sg-app`). The ConfigMap is mounted as a volume in the API pod at
`/app/evidence/`. On each `make ux` run, Ansible diffs the ConfigMap against the local
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
still a short-lived TLS cert, not a long-lived CA).

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

**Evidence:** The Keycloak `community.general.keycloak_user_federation` module does not
implement `check_mode`. In check mode it raises `AnsibleError: check mode not supported`.

**Decision:** All Keycloak federation tasks have `check_mode: false`. They are skipped in
dry-run passes (`--check` with `--diff`) but are always applied in real runs. This is
documented in `idempotency-allow.txt`.
