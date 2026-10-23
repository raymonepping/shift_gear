# Security model

Defence-in-depth at four layers:

1. **Vault policy** — what each bootstrap token may read/write/create.
2. **Kubernetes RBAC and NetworkPolicy** — what each pod may reach.
3. **mTLS** — the seal agent's listener requires client + server certificates.
4. **Secret hygiene** — no secret value in Terraform state; no Vault token in VSO application containers; the Agent demo isolates its token from its app.

---

## Secret boundary per tool

| Secret | Where it lives | Tool that writes it | Tool that reads it |
|---|---|---|---|
| `VAULT_LICENSE` | `.env` (local, gitignored) | Human | ansible prepare |
| Vault init keys and root tokens | `.secrets/` (local, gitignored) | ansible seal-init, bootstrap | Unseal/recovery; bootstrap policy and token-role reconciliation |
| Bootstrap tokens | `.secrets/tokens/` | ansible seal-init, bootstrap | tf seal, tf platform, ansible seal, ansible platform |
| AppRole role-id | Vault seal (`auth/approle/role/…/role-id`) | tf seal | ansible agent |
| AppRole secret-id | Kubernetes Secret `seal-agent-approle` | ansible agent | seal-agent pod (mounted) |
| KV secrets | Vault platform (`kv/data/shift-gear/…`) | ansible configure | VSO (via VaultStaticSecret), vault-agent |
| DB credentials | Vault platform (`database/creds/demo-reader`) | Vault (dynamic) | VSO (via VaultDynamicSecret) |
| TLS keys | `.secrets/tls/` | scripts/tls.sh | Kubernetes Secrets (ansible prepare), seal-agent pod |
| LDAP passwords | Vault KV (`kv/data/shift-gear/identity/…`) | ansible identity | Keycloak (LDAP bind), ansible identity |
| Pull secret | `.secrets/crc/` | Human | crc-up.sh |

---

## Terraform state: what is stored and why that is acceptable

| Root | What is in state | What is NOT in state |
|---|---|---|
| `infra` | Cluster data source reads (api_url, apps_domain, pod_cidr) — all discoverable from the running cluster; no secrets | — |
| `foundation` | Kubernetes object metadata (namespace names, SA names, Route specs) | — |
| `workloads` | Helm release values (image, replicas, config); Kubernetes object specs | TLS key material, licence, init output |
| `seal` | AppRole role names, transit key names, policy names | Secret-ids, role-ids, unseal keys |
| `platform` | Mount names, policy HCL text, token role specs | KV data, auth method credentials, DB passwords |

Terraform declares structure (mount paths, role names, policy text). Ansible writes values
(`no_log: true`). Secret values are never in state.

---

## The four bootstrap tokens

| Token | Created by | Used by | Capabilities (summary) |
|---|---|---|---|
| `sg-tf-seal` | ansible seal-init | tf seal | `sys/mounts`, `transit/keys`, `auth/approle/role` |
| `sg-ansible-seal` | ansible seal-init | ansible agent | `auth/approle/role/*/secret-id`, `auth/approle/role/*/role-id` |
| `sg-tf-platform` | ansible bootstrap | tf platform | `sys/mounts`, `sys/policies/acl`, `sys/auth` (read), token roles, audit |
| `sg-ansible-platform` | ansible bootstrap | ansible configure, identity, ux | `sys/auth`, `kv/data`, `database/config`, `pki-int`, identity |

Root tokens are retained in local init files with mode 0600. The bootstrap phases use them to reconcile bootstrap policies and token roles and to issue replacement scoped tokens; Terraform and the other configuration phases use scoped tokens.

Each bootstrap token is a renewable periodic orphan token with a 24-hour period. `seal-init` and `bootstrap` renew valid tokens on every real run.

The Ansible platform policy can revoke an individual
`database/creds/demo-reader/*` lease for the resilience proof. It cannot use
the generic or prefix endpoints, revoke another database role, or override the
scoped path with a body `lease_id`.

---

## Seal agent

The seal agent authenticates to the seal Vault with AppRole:

- **CIDR restriction:** the AppRole role has `secret_id_bound_cidrs` set to the pod CIDR
  (`10.217.0.0/22` on CRC, discovered from `pod_cidr` contract field). A secret-id cannot be used for a login from outside that CIDR; issuance from the controller is allowed.
- **NetworkPolicy:** `sg-vault-seal` namespace has a `deny-all` default with an explicit
  allow from `sg-vault` pods. Nothing else can reach the seal Vault directly.
- **mTLS:** the seal agent's listener requires client certificates signed by the project CA.
  Vault pods present their TLS certificate as a client certificate.
- **Rotation:** the rotator CronJob runs every six hours, replaces the ID in `seal-agent-approle`, and restarts the agent. `make rotation-proof` runs it twice and checks previous-ID absence, current lookup=200 and exactly one ID. The agent ID permits repeated logins and expires in 24 hours; the rotator ID permits repeated logins and has no expiry.

**No seal token on the cluster.** The cluster Vault pods unseal themselves via the transit
seal stanza: `seal { type="transit" }` in their Helm values. The seal agent never holds
a cluster Vault token — it only authenticates to the seal Vault.

---

## VSO: workloads hold nothing

VSO authenticates with Kubernetes auth using the projected SA token of the `vso-workloads` SA.
The destination Secrets contain application data and database credentials,
not a Vault token. Their application containers need no Vault configuration.

The resulting Kubernetes `Secret` objects (`app-config`, `db-creds`) are mounted read-only into
the workload pods. No Vault address in their environment.

`make verify` inspects Running pod specs in `sg-workloads` and `sg-app` for environment names containing `VAULT` and Vault-named `envFrom` sources. The named exceptions are `sg-app/sg-ui`, which calls Vault with the signed-in user’s token, and `vault-agent*` containers. This check does not inspect mounted file contents or arbitrary keys inside `envFrom` objects.

---

## Vault Agent sidecar

The `agent-demo` pod uses Vault Agent (init container + sidecar) with Kubernetes auth. The
pod SA token is the credential. The rendered file (`/vault/secrets/demo-secret`) is shared
via a memory-backed `emptyDir` volume. The token sink uses a separate
memory volume mounted only by the Agent containers. The application receives
no Vault token in its environment or shared secret directory.

---

## NetworkPolicies

Selecting ingress policies restrict the Vault servers, seal agent, identity
services, PostgreSQL and audit collector. There is no namespace-wide
default-deny or egress isolation. Workload-a/b and sg-ui have no selecting
ingress policy. See the [architecture policy table](architecture.md#networkpolicies)
for the actual callers and ports. Application authentication and Vault policy
remain necessary on the allowed paths.

---

## Demo-grade vs. production

| Aspect | This lab | Production change |
|---|---|---|
| Shamir seal on seal Vault | 1 share, threshold 1 | ≥ 5 shares, threshold 3; auto-unseal with HSM or KMS |
| CA | Project-local CA (scripts/tls.sh) | Public CA or enterprise PKI |
| Vault HA | 3 nodes, Raft, no storage HA on PVC | Integrated Storage on persistent storage with replication |
| LDAP | Single OpenLDAP pod, no replication | Active Directory or LDAP cluster |
| Bootstrap token period | 24 h renewable | Short-lived; machine identity via OIDC + Vault Agent |
| Init key storage | `.secrets/` local | Vault auto-unseal + operator custody (quorum) |
| Bootstrap tokens | Periodic orphan tokens, written to disk | Dynamic credentials via Vault's own OIDC provider or HCP Vault |
| State files | Local `.secrets/terraform/` | HCP Terraform workspaces with encryption |

---

## Audit

Terraform `platform` owns both audit devices at the root namespace. The file
device writes JSON to stdout for OpenShift log collection. The socket device
sends JSON lines to `sg-audit.sg-app.svc:9090`. Keeping stdout allows Vault to
serve while the socket collector is unavailable; requests fail when every audit
device fails.

Terraform `workloads` runs `sg-app/sg-audit` from a pinned UBI Node.js image,
mounting `collector/server.mjs` from a ConfigMap. The collector retains at most
1,000 projected entries in memory, returns at most 500 per request, and resets
its entries and counters on restart. It retains request metadata, display names,
policies and paths plus the names of HMAC-protected fields; it does not retain
those secret values. Metadata remains visible, so HMAC protection does not
make the stream anonymous.

NetworkPolicy allows TCP 9090 from Vault pods and HTTP 8080 from `sg-ui` only.
C02 adds a separate numeric-only metrics listener on 8081, restricted to the metrics-reader selector, and an optional OpenTelemetry or Prometheus service accessible only to the UI selector. When independently enabled, the collector also commits a narrower metadata projection to a bounded PVC archive: no actor names, policies, raw errors, payloads or credentials. Paths remain sensitive. Every signed-in user can read both audit views through authenticated fixed BFF endpoints. Internal service transport is HTTP with NetworkPolicy isolation; external connections require verified TLS. Local retention does not provide tamper evidence, external custody or isolated restore. See [the observability contract](observability.md).

Every signed-in console user may read the Audit page through the BFF. The page
reports live, unreachable or unconfigured state. In the earlier collector
restart proof, Vault kept answering 200 and reconnected on the next audited
request (recorded in `prompts/roadmap/LOG_claude.md`).

## Strengthening contract

Cleo's `sg-operator` policy may update only the existing `kv/data/shift-gear/config/app-config` path for the approved rotation action. General KV reads remain separate; this does not grant writes to identity credentials or structural Vault administration. Dirk's approver label does not imply admin/operator capability. Direct HTTP denials and KV version checks verify the boundary independently of button visibility.

Session expiry, signed provider logout, mutation Origin enforcement and audit readership are specified in the [session ADR](session-contract.md). Same-origin referrer policy permits browser-native logout forms to send the Origin required by the BFF; cross-origin referrers remain suppressed. Sessions and replay records are bounded and local to the single BFF instance. Routine BFF calls never substitute a bootstrap token.

The token reviewer is now Vault's projected ServiceAccount identity. Terraform declares the ServiceAccount/RBAC association without storing the reviewer JWT. Its former Secret is retired only after a fresh Kubernetes-auth proof; historical credential-bearing state remains protected under custody. See [credential operations](credential-operations.md), including the distinction between current-state cleanliness and confidential history.

## Selected Should identities

The BFF's `sg-ui-observer` projected Kubernetes token can GET four named VSO/deployment resources in `sg-workloads` and only `Deployment/seal-agent` in `sg-vault-seal`; it cannot read Secrets, list/watch, mutate or exec. Runtime Seal Vault, individual member health and identity discovery need no Vault or bootstrap token. Only namespace-and-pod-selected UI ingress to Seal Vault is added; the UI receives no Agent mTLS client credential and gains no Agent proxy access. All authenticated console users may inspect this bounded status metadata, as with the existing snapshot surfaces.

Separate maintenance identities are short-lived and stay on the operator host. The component-proof identity has only named fixture paths under `shift-gear` and self-revocation. Root-issued snapshot-reader identities can export encrypted Raft snapshots from each Vault, but cannot restore them, change policies or create tokens. Snapshot export is still sensitive authority: custody belongs with the scoped maintenance credentials and protected files, never with the console. No private key or plaintext from the PKI/Transit proof is published. Historical state, TLS backups and the new private snapshots remain confidential.

C03's dedicated Agent uses a projected audience-bound JWT mounted only into the sidecar. The application reads a mode-600 pgpass file on a read-only memory-volume mount, without a Vault token or Kubernetes Secret. Its Vault policy and database role are isolated from the existing VSO credential path and application table; the connection administrator remains privileged for role creation. See [the comparison and proof](agent-database-consumer.md).

Metrics and archive retention default to disabled. The core lab has no OpenTelemetry, Prometheus or archive PVC dependency; disabled browser sources issue no upstream fetch. Existing stores remain protected when optional runtime is disabled.
