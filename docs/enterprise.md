# Enterprise mapping

How each lab mechanism maps to its enterprise counterpart. Use this table when presenting
Shift Gear to an enterprise audience or when planning a production deployment.

---

## State and pipeline

| Lab mechanism | Enterprise counterpart | Notes |
|---|---|---|
| Five local state files (`.secrets/terraform/`) | HCP Terraform workspaces, one per root, with run triggers | Run triggers enforce the `infra → foundation → workloads → seal → platform` order; remote state eliminates local disk dependency |
| `make lab` (single command on a Mac) | CI/CD pipeline (GitHub Actions, Tekton, or GitLab CI) | Each phase becomes a pipeline stage; the `phases.txt` order is preserved |
| `VAULT_LICENSE` in `.env` | Dynamic credentials via Vault's own secret engine, or HCP Terraform variable sets | Never in a pipeline environment variable without masking |
| Bootstrap tokens in `.secrets/tokens/` | Dynamic credentials via Vault Agent on the CI runner, or OIDC token exchange | Short-lived, never stored; the runner authenticates with Kubernetes auth or OIDC |

---

## Automation

| Lab mechanism | Enterprise counterpart | Notes |
|---|---|---|
| `ansible-run.sh` on the Mac | Ansible Automation Platform (AAP) job templates | Each playbook becomes a job template; `phases.txt` order is a workflow template |
| `ansible-deps.sh` + `requirements.yml` | AAP execution environments (EE) with collection pins baked in | Exact same collection versions; no network access during job run |
| `make identity-verify` | AAP scheduled job (nightly) | Runs `identity-verify.yml` against the production cluster; results in AAP's job history |
| `make drift` | AAP scheduled check-mode job + HCP Terraform health assessments | Drift is detected before operators notice; alerts on non-zero changes |

---

## Secret delivery

| Lab mechanism | Enterprise counterpart | Notes |
|---|---|---|
| VSO `VaultStaticSecret` / `VaultDynamicSecret` | Same CRDs — VSO is production-grade; no change | The operator is cluster-scoped; scales to hundreds of namespaces |
| Vault Agent sidecar | Same pattern — Vault Agent is production-grade | Add `agent-inject` annotations or use the Vault Agent injector mutating webhook |
| No Vault token in workload pods | Same requirement — enforced by `make verify` | Production: add an OPA/Gatekeeper policy to reject pods with `VAULT_TOKEN` env |

---

## Identity

| Lab mechanism | Enterprise counterpart | Notes |
|---|---|---|
| Single OpenLDAP pod | Active Directory or LDAP cluster (replicated) | Vault LDAP auth config: same parameters; point to the enterprise LDAP |
| Keycloak (project-deployed) | Enterprise SSO (Okta, Azure AD, Ping) | Vault JWT auth is OIDC-standard; the `oidc_discovery_url` changes; nothing else does |
| Five demo users seeded by Ansible | Active Directory group membership managed by HR tools | Vault entities and groups map 1:1; `mount_accessor` references change |

---

## Seal chain

| Lab mechanism | Enterprise counterpart | Notes |
|---|---|---|
| Seal Vault (dedicated single-node Vault, Shamir 1/1) | Vault cluster dedicated to sealing (HA, Raft), auto-unsealed by AWS KMS or Azure Key Vault | The transit seal stanza in `vault/values.yaml` is unchanged; only the seal Vault's own unseal method changes |
| Seal agent (AppRole + mTLS, rotator CronJob) | Same pattern — or replace with Vault Agent auto-auth + Kubernetes auth on the seal Vault | CIDR restriction still applies; NetworkPolicy still applies |
| Manual unseal key storage (`.secrets/`) | Vault's own auto-unseal via HSM or KMS | No human ever holds the unseal key in production |

---

## Observability and audit

| Lab mechanism | Enterprise counterpart | Notes |
|---|---|---|
| File audit device on a PVC | File audit device on persistent storage, forwarded to a SIEM (Splunk, QRadar) via a log shipper | Vault audit log format is HMAC-redacted JSON; same in production |
| Socket audit device | Socket audit to a sidecar that forwards to the SIEM | The `127.0.0.1:9090` socket in the lab becomes a pod-local sidecar in production |
| `make verify` gate files (`.build/gates/`) | Audit trail in HCP Terraform plan history + AAP job history | Every apply and check-mode run is recorded with full output |

---

## Substrate

| Lab mechanism | Enterprise counterpart | Notes |
|---|---|---|
| CRC (single-node OpenShift on a Mac) | Any OpenShift cluster (ROSA, vSphere, bare-metal OCP, ARO) | Replace `terraform/infra/` only; re-emit the contract; run `make lab` |
| Local `crc` CLI | OpenShift installer or managed service provisioning | `scripts/crc-*.sh` are the only files that change |
| `.secrets/kube/config` (CRC kubeconfig) | SA token + OIDC kubeconfig for the target cluster | `var.kubeconfig_path` points to the new config |

---

## The lab→enterprise principle

The Shift Gear lab is not a toy. Every mechanism has a direct enterprise counterpart. The
substrate contract (`terraform/infra/`) is the only thing that changes when the cluster changes.
The tool boundary (four bootstrap tokens, enforced by Vault policy) is what prevents credential
sprawl at enterprise scale — not a team agreement, but a policy that `make boundary` verifies
on every run.

At enterprise scale:
- HCP Terraform workspaces replace local state files and add run triggers, cost estimates, and
  policy checks (Sentinel).
- AAP replaces `ansible-run.sh` and adds RBAC, audit logs, and credential injection without
  exposing secrets to operators.
- The Vault Operator (VSO) scales to every namespace in the cluster — no credential in any pod.
- The substrate contract means a migration from CRC to ROSA requires one Terraform variable
  change and one `make infra` run.

For each lab mechanism, the documentation above names the enterprise counterpart. The same
`docs/lessons-learned.md` entry applies at scale; the same `docs/decisions.md` rationale holds.
