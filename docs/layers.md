# Layers

Per-phase breakdown of the full `make lab` run. Each phase is atomic: it either completes
fully or fails with an explicit error. On failure, `lab.sh` prints the exact command to resume.

---

## Phase 1 — `tf infra`

| | |
|---|---|
| **Tool** | Terraform |
| **Root** | `terraform/infra/` |
| **Inputs** | Running CRC cluster; `var.api_url`; `var.kubeconfig_path` |
| **Outputs** | `.build/terraform/infra.json` — `cluster.apps_domain`, `cluster.pod_cidr`, `cluster.kubeconfig_path`, `cluster.ingress_ca_path`, `cluster.registry_host` |
| **State** | `.secrets/terraform/infra/terraform.tfstate` |
| **Creates** | Nothing — read-only discovery |
| **Idempotency** | Plan always empty on second run (data sources only) |
| **Resume** | `make infra` |

---

## Phase 2 — `tf foundation`

| | |
|---|---|
| **Tool** | Terraform |
| **Root** | `terraform/foundation/` |
| **Inputs** | `infra.json` (apps_domain, pod_cidr, kubeconfig_path) |
| **Outputs** | `.build/terraform/foundation.json` |
| **Creates** | Namespaces (`sg-vault`, `sg-vault-seal`, `sg-identity`, `sg-workloads`, `sg-app`); RBAC (SAs, CRBs); NetworkPolicies; Routes; VSO Subscription; ImageStream + BuildConfig for OpenLDAP |
| **Idempotency** | Kubernetes resources are declarative; plan empty on second run |
| **Resume** | `make foundation` |

---

## Phase 3 — `ansible prepare`

| | |
|---|---|
| **Tool** | Ansible |
| **Role** | `sg_prepare` |
| **Inputs** | `.env` (VAULT_LICENSE); `.secrets/crc/pull-secret.txt`; `infra.json` |
| **Outputs** | TLS certs in `.secrets/tls/`; Kubernetes Secrets: `vault-license`, `vault-tls`, `vault-seal-tls`, `keycloak-tls`, CA ConfigMaps |
| **Waits for** | VSO CSV `phase=Succeeded` (polls every 30 s, up to 10 min) |
| **Idempotency** | `changed=0` — certs are not regenerated if they already exist and are valid |
| **Resume** | `make prepare` |

---

## Phase 4 — `tf workloads`

| | |
|---|---|
| **Tool** | Terraform |
| **Root** | `terraform/workloads/` |
| **Inputs** | `foundation.json`; `infra.json`; Secrets created in `prepare` |
| **Outputs** | `.build/terraform/workloads.json` — seal Vault address, cluster Vault address |
| **Creates** | Vault seal Helm release (1 node); Vault cluster Helm release (3 nodes); seal-agent Deployment; rotator CronJob; OpenLDAP Deployment + PVC; Keycloak Deployment + PVC; PostgreSQL StatefulSet; NetworkPolicies (allow rules); VSO VaultConnection + VaultAuth + VaultStaticSecret + VaultDynamicSecret; workload-a + workload-b Deployments; agent-demo Deployment |
| **Idempotency** | Helm releases compare values + chart version; plan empty on second run |
| **Resume** | `make workloads` |

---

## Phase 5 — `ansible seal-init`

| | |
|---|---|
| **Tool** | Ansible |
| **Role** | `sg_seal_init` |
| **Inputs** | `workloads.json` (seal Vault address); TLS CA |
| **Outputs** | `.secrets/tokens/tf-seal`, `.secrets/tokens/ansible-seal`; `.build/seal-init.json` (init result, no_log) |
| **Does** | Initialises seal Vault (1 share, threshold 1); unseals; enables transit auth method; creates bootstrap policies (`sg-tf-seal.hcl`, `sg-ansible-seal.hcl`); mints bootstrap tokens; writes tokens to `.secrets/tokens/` |
| **Idempotency** | Skips init if already initialised; skips token creation if tokens exist and are valid |
| **Resume** | `make seal-init` |

---

## Phase 6 — `tf seal`

| | |
|---|---|
| **Tool** | Terraform |
| **Root** | `terraform/seal/` |
| **Inputs** | `workloads.json`; `.secrets/tokens/tf-seal` |
| **Outputs** | `.build/terraform/seal.json` |
| **Creates** | Transit mount on seal Vault; `autounseal` transit key; AppRole auth method; `sg-seal-autounseal` role; `sg-seal-rotator` role |
| **Token** | `sg-tf-seal` — may create mounts and AppRole roles; may NOT mint secret-ids |
| **Idempotency** | Plan empty on second run |
| **Resume** | `make seal` |

---

## Phase 7 — `ansible agent`

| | |
|---|---|
| **Tool** | Ansible |
| **Role** | `sg_seal_agent` |
| **Inputs** | `seal.json`; `.secrets/tokens/ansible-seal`; `workloads.json` |
| **Outputs** | Kubernetes Secret `seal-agent-approle` (role-id + secret-id); `.build/agent-proof.json` |
| **Does** | Reads AppRole role-id; generates secret-id; writes them to `seal-agent-approle` Secret; verifies the agent can authenticate and reach the transit key; sets rotator credentials |
| **Token** | `sg-ansible-seal` — may mint secret-ids; may NOT create mounts |
| **Idempotency** | Secret-ids are single-use; a new one is generated each run (this is intentional — the old one is expired) |
| **Resume** | `make agent` |

---

## Phase 8 — `ansible bootstrap`

| | |
|---|---|
| **Tool** | Ansible |
| **Role** | `sg_bootstrap` |
| **Inputs** | `workloads.json` (cluster Vault address); TLS CA |
| **Outputs** | `.secrets/tokens/tf-platform`, `.secrets/tokens/ansible-platform`; `.build/bootstrap.json` |
| **Does** | Initialises cluster Vault (1 share for demo, stored encrypted by Vault); raft join for vault-1, vault-2; enables transit seal auto-unseal; creates platform bootstrap policies; mints four bootstrap tokens |
| **Idempotency** | Skips if already initialised; token creation is idempotent via token role |
| **Resume** | `make bootstrap` |

---

## Phase 9 — `tf platform`

| | |
|---|---|
| **Tool** | Terraform |
| **Root** | `terraform/platform/` |
| **Inputs** | `workloads.json`; `.secrets/tokens/tf-platform` |
| **Outputs** | `.build/terraform/platform.json` |
| **Creates** | Vault enterprise namespace `shift-gear`; mounts: `kv`, `transit`, `pki-int`, `database`, `sys/audit`; PKI intermediate CA; policies: `sg-engineer`, `sg-operator`, `sg-approver`, `sg-auditor`, `sg-vso`, `sg-api`, `sg-agent-demo`; `sg-ui` token role (CIDR-bound to pod_cidr); file audit device |
| **Token** | `sg-tf-platform` — may create mounts and policies; may NOT enable auth or write KV data |
| **Idempotency** | Plan empty on second run |
| **Resume** | `make platform` |

---

## Phase 10 — `ansible identity`

| | |
|---|---|
| **Tool** | Ansible |
| **Role** | `sg_identity` |
| **Inputs** | `platform.json`; `.secrets/tokens/ansible-platform`; `infra.json` |
| **Does** | Seeds OpenLDAP users + groups (via `kubernetes.core.k8s_exec`); configures Keycloak realm `shift-gear`, LDAP federation, OIDC client; enables OIDC, JWT, LDAP auth methods on Vault; creates identity groups and entities |
| **Idempotency** | LDAP entries: `ldapadd -c` skips existing; Keycloak: idempotent via admin API; Vault auth: `create_or_update` |
| **Resume** | `make identity` |

---

## Phase 11 — `ansible configure`

| | |
|---|---|
| **Tool** | Ansible |
| **Role** | `sg_configure` |
| **Inputs** | `platform.json`; `.secrets/tokens/ansible-platform`; `infra.json` |
| **Does** | Enables Kubernetes auth (sg-api role, sg-agent-demo role); configures AppRole (sg-automation); configures cert auth (internal-client); DB secrets engine (PostgreSQL, demo-reader role); KV seeds (`app-config`, `agent-demo`); socket audit device; seeds KV for agent demo |
| **Idempotency** | All tasks are idempotent; `changed=0` on second run |
| **Resume** | `make configure` |

---

## Phase 12 — `ansible ux`

| | |
|---|---|
| **Tool** | Ansible |
| **Role** | `sg_ux` |
| **Inputs** | Evidence files under `.build/`; `infra.json` |
| **Does** | Triggers BuildConfig for the UI image; waits for the build to complete; syncs evidence files as a ConfigMap (`sg-evidence`) into `sg-app`; restarts the API deployment to pick up new evidence |
| **Idempotency** | Build is only triggered when Dockerfile or source has changed (BuildConfig source hash); evidence sync is `changed=0` when evidence files are unchanged |
| **Resume** | `make ux` |

---

## Phase 13 — `ansible validate`

| | |
|---|---|
| **Tool** | Ansible |
| **Role** | `sg_validate` |
| **Inputs** | `platform.json`; `.secrets/tokens/ansible-platform`; running stack |
| **Outputs** | `.build/validation.json`; `.build/gates/validation.json` |
| **Checks** | Vault initialized + unsealed; HA active+voters; all mounts present; all policies present; seal Vault healthy; Vault UI Route answers; Keycloak OIDC discovery; VSO Secrets synced; identity-verify passthrough |
| **Idempotency** | Read-only — always `changed=0` |
| **Resume** | `make validate` |

---

## Gates (after phase 13)

| Gate | What it checks | Output |
|---|---|---|
| `idempotency` | Every Ansible phase: `changed=0` (exceptions in `idempotency-allow.txt`) | `.build/gates/idempotency.json` |
| `secret-scan` | Grep for token patterns, PEM keys, licence prefix in tracked files | `.build/gates/secret-scan.json` |
| `boundary` | 19 `sys/capabilities-self` checks across all four bootstrap tokens | stdout only (no gate file) |

---

## Adding a phase

1. Add a line to `scripts/phases.txt`: `tf <root>` or `ansible <playbook>`.
2. Create the Terraform root or Ansible playbook.
3. The phase is automatically picked up by `lab.sh`, `idempotency.sh`, `drift.sh`, and `layers.sh`.
