# SHIFT GEAR — Master Vision & Reference

## Vault Enterprise on OpenShift — built by Terraform, decorated by Ansible, consumed through the Vault Secrets Operator

> **Read-only reference.** This file is not an execution prompt. Every
> execution prompt (`01_01` through `docs/02`) carries a **System Prompt
> Header** (persona, audiences, invariants, deliverables standard) that
> must be read and honoured before any work in that prompt begins. When a
> prompt and this file disagree, **this file wins**; record the conflict in
> that prompt's execution log.

You are working on a new engineering project called **Shift Gear**.

Shift Gear is a local, reproducible reference system for **HashiCorp Vault
Enterprise running on OpenShift**. Today that OpenShift is OpenShift Local
(CRC) on an Apple Silicon Mac. Tomorrow it could be a bare-metal OCP cluster,
ROSA, or anything else that speaks the OpenShift API. The architecture does
not change. It is not a production product. It is a technically credible,
visually polished reference that demonstrates every major Vault Enterprise
operational concern in one coherent system.

---

## 1. Core thesis

> **The architecture is Vault on OpenShift. CRC is the current substrate.**
>
> **Terraform builds the house. Ansible decorates it.** Vault enforces the
> line between them. The Vault Secrets Operator delivers secrets to
> workloads that never hold a Vault token.

The ownership rule from the series, applied without exception:

> If it has an API and a lifecycle, it is Terraform's.
> If it has an order and a moment, it is Ansible's.

Shift Gear is the synthesis of four predecessors:

| Project | Contribution |
| --- | --- |
| `../multi_pass` | Multipass + Terraform + Ansible: the original baton between tools; the substrate contract idea |
| `../red_pass` | Multipass + Ansible only: Ansible depth, people (OpenLDAP + Keycloak), the seal agent, evidence-first validation, the console |
| `../golden_ticket` | Multipass + Terraform + Ansible rebuilt on the lessons: four scoped bootstrap tokens, Terraform for Vault structure, the phase list, the gates (idempotency, drift, secret scan), the Layers page, D1–D14 |
| `../red_doors` | OpenShift Local + Terraform: Vault Helm on OpenShift, `wait-for-seal-vault`, VSO, Nuxt 4 + Express BFF on OpenShift, 12 lessons |

Shift Gear takes the OpenShift target from **Red Doors**, the seal chain and
the tool boundary from **Golden Ticket** (which took the seal agent from
**Red Pass**), and the console from **Golden Ticket + Red Doors**.

The audience leaves understanding:

- How Terraform builds Vault Enterprise HA on OpenShift (Helm releases,
  namespaces, Routes, NetworkPolicies) and the structure inside Vault
  (namespaces, mounts, policies), without anyone touching a Vault UI.
- How Ansible does what has an order and a moment: init, unseal, the seal
  agent's credentials and their rotation, people, auth methods, seeds, proof.
- How the Vault Secrets Operator (`VaultConnection`, `VaultAuth`,
  `VaultStaticSecret`, `VaultDynamicSecret`) removes Vault credentials from
  application pods entirely.
- How the cluster auto-unseals through a seal agent, so **no Vault pod holds
  a seal token**.
- **Why the substrate does not matter**: the Vault architecture, the Ansible
  playbooks and the VSO resources are identical whether the OpenShift
  cluster was created by CRC, vSphere IPI or a cloud provider. The only
  thing that changes is `terraform/infra/`.

---

## 2. The substrate contract

This is the central architectural idea, inherited from `../multi_pass` and
written down as a contract in `../golden_ticket/docs/substrate-contract.md`.

> *"Multipass is not the architecture. I designed Vault on three RHEL
> machines. Multipass happens to create those machines."*

> **CRC is not the architecture. The architecture is Vault on OpenShift.**

`terraform/infra/` is the only layer that knows about the substrate. CRC's
own lifecycle (create, start, stop, delete) is driven by `scripts/crc-*.sh`
through `make crc-*`, because no maintained Terraform provider manages CRC
(`todoroff/crc` does not exist; checked 2026-10-08). `terraform/infra/` is
therefore a **contract root**: it reads the running cluster and emits the
contract. Every layer above it consumes only this output:

```hcl
# terraform/infra/outputs.tf — the substrate contract
output "cluster" {
  description = "OpenShift cluster connection contract. Stable across substrate implementations."
  value = {
    api_url         = "https://api.crc.testing:6443"   # cluster API endpoint
    apps_domain     = "apps-crc.testing"               # wildcard Route domain (read from ingresses.config.openshift.io/cluster)
    pod_cidr        = "10.217.0.0/22"                  # cluster network (read from networks.config.openshift.io/cluster)
    kubeconfig_path = ".secrets/kube/config"           # kubeconfig (gitignored)
    ingress_ca_path = ".secrets/kube/ingress-ca.pem"   # router CA, for edge Routes (Keycloak, console)
    registry_host   = "image-registry.openshift-image-registry.svc:5000"
  }
}
```

Values are **discovered from the cluster** wherever the OpenShift API offers
them (apps domain, pod CIDR, ingress CA), not typed in. Only the API URL and
the kubeconfig location are substrate-specific inputs.

Route hostnames (`vault.<apps_domain>`, `vault-seal.<apps_domain>`,
`keycloak.<apps_domain>`, `shiftgear.<apps_domain>`) are **derived** by the
roots and playbooks above infra from `apps_domain`; they are not part of the
contract.

| Substrate | `terraform/infra/` implementation |
| --- | --- |
| OpenShift Local (CRC) — **current** | contract root: `kubernetes` provider data sources against the CRC kubeconfig; CRC lifecycle in `scripts/crc-*.sh` |
| vSphere IPI | `openshift-install` driven by its own pipeline; infra = the same contract root against the resulting kubeconfig |
| ROSA | `terraform-redhat/rhcs` (`rhcs_cluster_rosa_classic` / HCP) + the same contract outputs |
| Existing OCP | contract root only (import: kubeconfig + data sources) |

When the substrate changes: replace `terraform/infra/`, make the `cluster`
output true, run `make lab`. Nothing above infra changes. Document this in
`docs/substrate-contract.md` (prompt docs/01), with a `terraform test` that
asserts the contract's shape (every field present and non-empty).

---

## 3. Decisions already made (do not re-litigate)

| Area | Decision |
| --- | --- |
| Platform | **Full OpenShift Local** (CRC 2.64 / OpenShift 4.22.14, arm64, `vfkit`). Not MicroShift. |
| Vault | **Vault Enterprise 2.1.0-ent** (arm64 digest recorded), **3-node Raft HA**, official Helm chart, `global.openshift=true`. |
| Seal chain | **Same as golden_ticket, from day one.** Seal Vault (1 node, Shamir 1/1, own namespace) holds the Transit key `autounseal`. A **seal agent** (Vault Agent Deployment) authenticates with **AppRole**, runs `api_proxy { use_auto_auth_token = "force" }` behind a listener that **requires a client certificate** from the project CA. Cluster pods use `seal "transit"` pointed at the agent with their own client certificate and **hold no seal token**. A **rotator CronJob** replaces the agent's secret-id every 6 hours on the wall clock and destroys the previous one. No long-lived seal token exists anywhere. |
| Tool boundary | **Four bootstrap tokens, enforced by Vault policy** (golden_ticket): `sg-tf-seal` / `sg-ansible-seal` on the seal Vault, `sg-tf-platform` / `sg-ansible-platform` on the cluster. Periodic orphan tokens (period 24h) issued through token roles that may issue only that one policy; re-issued by Ansible when expired. Ansible writes the four bootstrap policies with the root token; root is break-glass afterwards (kept, never used for routine work, never revoked). No separate "admin token". |
| Terraform roots | **Five roots, five state files** in `.secrets/terraform/<root>/` (`0600`). Each seam is forced either by provider-configuration timing (a Vault provider cannot use a token that does not exist yet) or by the rule that secret values never enter state. See §4. |
| Secret values | **Never in Terraform state.** Licence, TLS private keys, init output, tokens, secret-ids, identity passwords, client secrets and the DB admin password are created or written by Ansible (`no_log`), as Kubernetes `Secret`s or into Vault. Terraform references Secrets **by name** only. |
| Runtime secret delivery | **Vault Secrets Operator** (certified, OperatorHub, channel `stable`): `VaultStaticSecret` and `VaultDynamicSecret` sync into OpenShift `Secret`s. Application pods never hold Vault tokens. |
| Workload agent demo | Separately from the seal agent, one demo pod in `sg-app` runs a **Vault Agent sidecar** (Kubernetes auth) for workloads that cannot use VSO. Its token comes from auto-auth and is re-acquired by the agent; validation checks it is renewable and fresh. |
| Humans | **OpenLDAP + Keycloak** in-cluster. Terraform deploys them (the house); Ansible configures them (realm, federation, clients, users, Vault auth). Reuse `../red_doors/deploy/identity/` (OpenLDAP built from Alpine for `restricted-v2`) and `../golden_ticket/ansible/roles/identity_*`. |
| UI/UX | **Nuxt 4 SPA + Nitro BFF + Express API** (Red Doors shape). UI code starts from `../golden_ticket/ux/` (Layers page, ownership from Terraform, gates), with `../red_doors/ui/` and `../red_doors/api/` for the OpenShift BFF/API shape. Built in-cluster (BuildConfig + ImageStream). Vault daylight glass design system (`vault-ui-design` skill). |
| Evidence to the console | `.build/*.json` (non-secret) is synced by Ansible into ConfigMap `sg-evidence` in `sg-app` after the secret scan has passed, and mounted read-only into the API pod. A pod cannot mount files from the Mac. |
| Licence | `VAULT_LICENSE` from `.env` (allow-listed parser) → Ansible writes `Secret vault-license` in `sg-vault-seal` and `sg-vault`. Never a file in the repository, never a Terraform variable, never `extra_vars`. |
| RHSM | **Not used.** There is no RHEL host to register: CRC pulls Red Hat images with the pull secret, and the in-cluster builds use UBI images, which need no subscription. The `RHSM_*` keys in `.env` are ignored and documented as such (README). Do not add `bootstrap.yml` / `rhel-unregister.yml`. |
| Tooling | Make + Terraform ≥ 1.11 (`hashicorp/kubernetes`, `hashicorp/helm`, `hashicorp/vault`) + `oc` + Ansible (`kubernetes.core`, `community.general`, `community.crypto`) + `jq`. Secrets under `.secrets/` (gitignored). |

---

## 4. Architecture

```text
OpenShift cluster  [substrate: CRC today; any OCP cluster tomorrow]
├── sg-vault-seal    seal Vault (1 pod, Shamir 1/1) — Transit key `autounseal`
│                    seal-agent (Vault Agent, AppRole, api_proxy force, mTLS :8200)
│                    seal-rotator CronJob (every 6 h, wall clock)
├── sg-vault         Vault Enterprise ×3 (Raft HA), seal "transit" → seal-agent, no seal token
│                    Route vault.<apps_domain> (passthrough)
├── sg-identity      OpenLDAP + Keycloak (realm `shift-gear`), Route keycloak.<apps_domain>
├── sg-workloads     demo workloads + Postgres, secrets via VSO only
├── sg-app           shift-gear-api (Express) + shift-gear-ui (Nuxt 4), agent-demo pod
│                    Route shiftgear.<apps_domain>; ConfigMap sg-evidence
└── openshift-operators  Vault Secrets Operator (certified)
```

NetworkPolicies take the role firewalld had on the VMs: the seal agent
accepts connections only from the Vault pods in `sg-vault`; the seal Vault
accepts AppRole logins only from the agent and the rotator (plus the router,
for operator access through its passthrough Route).

### The phase list (`scripts/phases.txt`, the only one)

```text
tf      infra       substrate contract: api_url, apps_domain, pod_cidr, kubeconfig, ingress CA
tf      foundation  namespaces, RBAC + SAs, NetworkPolicies, Routes, VSO Subscription, ImageStreams + BuildConfigs
ansible prepare     project CA + certs, licence + TLS Secrets, CA ConfigMaps; waits for the VSO CSV to be Succeeded
tf      workloads   Helm: seal Vault, Vault ×3; seal-agent + rotator; OpenLDAP, Keycloak, Postgres; VSO resources; demo workloads; API/UI Deployments
ansible seal-init   seal Vault: init 1/1, unseal, seal bootstrap policies, sg-tf-seal + sg-ansible-seal tokens
tf      seal        transit mount + `autounseal` key, policies, AppRole roles (seal-autounseal, seal-rotator)
ansible agent       secret-ids → Secrets, seal agent ready and proven from a Vault pod, rotator credentials
ansible bootstrap   cluster init (recovery keys), raft join check, platform bootstrap policies, sg-tf-platform + sg-ansible-platform tokens
tf      platform    namespace shift-gear, mounts (kv, transit, pki, pki-int, database), ACL policies, token roles, file audit device
ansible identity    LDAP seed, Keycloak realm/clients/federation, Vault oidc + jwt + ldap auth, external groups
ansible configure   kubernetes/approle/cert auth + roles, DB connection + rotate-root, KV seeds, agent demo, socket audit device
ansible ux          UI/API image builds, evidence ConfigMap sync
ansible validate    read-only end-to-end proof → .build/validation.json
        gates       idempotency (real re-run, changed=0) · drift (plans empty + check mode) · secret scan
```

`make lab` runs the phases in this order, then the gates, then writes the
convergence stamp and syncs the evidence one last time. On failure it prints
the exact phase to resume. There is **no `site.yml`**: neither tool alone can
build this lab.

Why each Terraform seam exists:

| Seam | Reason |
| --- | --- |
| infra → foundation | the contract must exist before anything reads it |
| foundation → prepare → workloads | Secrets with values (licence, TLS keys) come from Ansible and must exist before pods mount them; the VSO CRDs must exist before Terraform can plan `VaultConnection` etc. |
| workloads → seal-init → seal | the Vault provider for the seal Vault needs `sg-tf-seal`, which exists only after init |
| seal → agent → bootstrap → platform | the cluster can only initialise once the agent unseals it; the platform provider needs `sg-tf-platform` |

Releases whose pods cannot become ready until a later phase (main Vault,
seal agent) use `wait = false`; the Ansible phase that completes them
asserts their readiness.

### Ownership

| Domain | Owner | How |
| --- | --- | --- |
| CRC lifecycle | Make + scripts | `make crc-*` |
| Cluster contract | Terraform `infra` | data sources → `cluster` output |
| Namespaces, RBAC, NetworkPolicies, Routes, VSO Subscription, build objects | Terraform `foundation` | `kubernetes` provider |
| Helm releases and Deployments (Vault, seal agent, rotator, identity stack, Postgres, workloads, app), VSO resources | Terraform `workloads` | `helm` + `kubernetes` providers; Secrets referenced by name |
| TLS, licence, Secrets with values | Ansible `prepare` (and later phases) | `kubernetes.core.k8s`, `no_log` |
| Init, unseal, raft join, bootstrap tokens | Ansible `seal-init`, `bootstrap` | Vault HTTP API (`uri`) |
| Seal Vault structure (transit mount + key, policies, AppRole roles) | Terraform `seal` | Vault provider, `sg-tf-seal` |
| Secret-ids, agent readiness, rotator credentials | Ansible `agent` | `sg-ansible-seal` |
| Cluster structure (namespace, mounts, policies, token roles, file audit) | Terraform `platform` | Vault provider, `sg-tf-platform` |
| Auth methods + roles, identity groups/aliases, KV data, DB connection, socket audit | Ansible `identity`, `configure` | `sg-ansible-platform` |
| Images, evidence | Ansible `ux` | `oc start-build`, ConfigMap |
| Validation and evidence | Ansible `validate` | `.build/validation.json` |
| Phase order and gates | Make | `scripts/phases.txt`, `scripts/lab.sh` |

### The boundary Vault enforces

| Vault | Terraform (structure) | Ansible (configuration) |
| --- | --- | --- |
| seal Vault | `sg-tf-seal`: transit mount + key, seal policies, AppRole mount + roles — never a secret-id | `sg-ansible-seal`: read role-ids, mint/destroy secret-ids — never a mount, policy or role |
| cluster | `sg-tf-platform`: namespaces, mounts, ACL policies, token roles, audit devices, licence status — never an auth method, identity or secret data; never delete `kv/` | `sg-ansible-platform`: auth methods, identity groups/aliases, `kv/data/shift-gear/*`, DB connection, tokens via Terraform-made roles — never a mount or policy |

Every bootstrap policy also denies writes to `sg-tf-*` and `sg-ansible-*`
policies, so no tool can widen its own access. `make boundary` proves the
table with 19 `sys/capabilities-self` checks (`scripts/boundary-check.sh`).

### Contracts between the tools

| From → to | Contract |
| --- | --- |
| Terraform → everyone | `cluster` output of `infra` |
| Terraform → Ansible | every root's outputs, written by `scripts/tf-run.sh` to `.build/terraform/<root>.json` (non-secret) and loaded by `ansible/group_vars/all/terraform.yml`; Ansible's preamble asserts each file exists and is newer than its state |
| Ansible → Terraform | the four token files in `.secrets/tokens/`, exported only as `VAULT_TOKEN` for their own root by `tf-run.sh` (which also unsets `VAULT_NAMESPACE`) |
| Terraform → Ansible (validation) | `platform` outputs (namespaces, mounts, policies, token roles) — `validate.yml` asserts each exists |
| Everything → the console | `.build/*.json` → ConfigMap `sg-evidence` |

Ansible's inventory is **localhost only** (`connection: local`): it talks to
the Vault API through the Routes with the project CA, and to OpenShift with
`kubernetes.core` and the contract's kubeconfig. There is no SSH anywhere.

---

## 5. Reconnaissance — reuse, don't copy blindly

Before writing code in any prompt, read the referenced predecessor files and
list in the execution log what you reuse and what you change:

- `../red_doors` — Helm values on OpenShift, `wait-for-seal-vault`, TLS
  script, VSO install + CSV gate, OpenLDAP from Alpine, Nuxt/Express on
  OpenShift, OIDC BFF, Playwright + axe. **OpenShift reference.**
- `../golden_ticket` — the tool boundary (`policies/bootstrap/`), the seal
  agent and rotator (`ansible/roles/seal_agent`), `scripts/phases.txt`,
  `lab.sh`, `idempotency.sh`, `drift.sh`, `secret-scan.sh`,
  `boundary-check.sh`, `tf-run.sh`, `gt_stats` callback, `validate.yml`,
  `ux/`, `docs/decisions.md` (D1–D14), `docs/lessons-learned.md`.
  **Architecture reference.**
- `../red_pass` — Ansible role idioms (compare-before-write, check-mode
  honesty), identity roles.
- `../multi_pass` — the original contract idea.

### Consolidated lessons (apply all of them)

**From Red Doors** (`../red_doors/prompts/base_project/00_01_red_doors.md`,
full text there):

1. Transit seal **token** expiry silently crash-loops Vault — Shift Gear
   removes the seal token entirely (seal agent); the *agent's* secret-id
   expiry is the equivalent risk: `make up` re-mints a secret-id that no
   longer exists (golden_ticket pattern) and validation checks its age.
2. Certificates expire: every cert has an owner that renews it; consumers
   report `cert_expired` on `/health` (503) instead of crash-looping.
3. AppRole lockout: bound it (e.g. 3 failures / 30 s) on demo roles.
4. Never write back `vault read -field=token_policies`; declare full lists.
5. arm64 only: check every image (`oc image info --show-multiarch`).
6. `restricted-v2` runs a random UID; no `anyuid` without written reason.
7. macOS xattrs break builds: `xattr -rc`, `._*` in `.dockerignore`,
   `COPYFILE_DISABLE=1`.
8. Postgres loopback trusts everything: test over the service hostname.
9. Never fabricate evidence: missing data shows as missing.
10. Kubernetes `$(VAR)` expansion is order-dependent: `api_addr` uses
    `$(POD_IP)`; check `helm template` for literal `$(`.
11. A transit-sealed Vault exits at start while its seal is unreachable:
    `wait-for-seal-vault` init container (in Shift Gear it waits for the
    **seal agent** to answer, through mTLS).
12. A control group alone does not stop self-approval: Sentinel EGP.

**From the Multipass labs and Golden Ticket:**

13. **No RHSM on OpenShift** (decision §3). Don't invent a target for it.
14. **Ansible reads Terraform outputs, never a hand-written inventory.**
    `tf-run.sh` writes `.build/terraform/<root>.json`; the preamble refuses
    stale or missing files.
15. **Agent tokens come from auto-auth and must stay renewable.** The seal
    agent's token is re-acquired from AppRole; the demo agent's from
    Kubernetes auth. Validation checks `renewable=true` and remaining TTL.
16. **Set the Vault namespace explicitly** on every task and resource;
    `tf-run.sh` unsets `VAULT_NAMESPACE` (a leaked value double-prefixes
    every path).
17. **The OpenShift pull secret is a prerequisite**: `make crc-up` fails
    loudly if `.secrets/crc/pull-secret.json` is missing.
18. **The VSO CSV must reach `Succeeded` before any VSO resource is
    planned or applied** (Ansible `prepare` waits for it).
19. **The substrate is not the architecture.** Only `terraform/infra/` and
    `scripts/crc-*.sh` may mention `crc`, `vfkit`, `api.crc.testing` or
    `apps-crc.testing`. A grep proves it in `make check`.
20. **The tool boundary is enforced by Vault** (four tokens, §4). If a task
    needs a capability its token lacks, it is in the wrong tool.
21. **Separate roots, separate state**, each seam justified (§4).
22. **`prevent_destroy` is a first line, not protection** (D11): it lives
    in the block it protects. Put it on the seal transit mount + key and on
    `kv/`, **and** deny Terraform's token `delete` on those mounts in Vault
    policy. Prove it by applying a deleted block (403).
23. **TLS `notBefore` one hour back** on every certificate (clock skew).
24. **Vault and seal-agent certificates carry `serverAuth` + `clientAuth`**:
    the Vault pods present theirs to the seal agent's mTLS listener.
25. **`secret-scan.sh` scans for known values and patterns** (`hv[sbr]\.`,
    PEM private keys with a body, the licence prefix) across state,
    backups, `.build/`, logs and tracked files; state files are `0600`.
26. **Idempotency is a real re-run; check mode is drift** (D14). Some
    modules cannot prove themselves in check mode (Keycloak user
    federation): skip those in check mode with a comment; the real re-run
    still covers them.
27. **Rebuild from nothing before calling it done.** In golden_ticket the
    from-nothing rebuild found three first-run bugs no converged re-run
    could show (a restart on a missing unit, a container chowning its
    certificate directory, Keycloak filling realm defaults on the first
    update). Expect the same class here.
28. **A data source scoped inside a `check` block is re-read at every
    apply** and keeps `plan -detailed-exitcode` at 2 (D10).
29. **Licence metadata, not the licence**: if `platform` reads
    `sys/license/status` (licence-aware engines), only feature names are
    unmarked with `nonsensitive()`; the scan checks the licence prefix (D9).
30. **`no_log` does not censor every failure line** (D12): never build a
    URL or header name from a variable that could hold a secret.
31. **A token role bound to one address refuses the caller behind a
    proxy**: bind console/API token roles to what Vault actually sees.

---

## 6. Principles

- **Substrate independence**: only `terraform/infra/` knows the substrate.
- **Layer separation**: Terraform builds, Ansible decorates, VSO delivers.
  Nothing crosses layers in the wrong direction; Vault enforces it.
- **Idempotent from zero**: `make crc-up && make lab` on a fresh CRC brings
  everything up; a second `make lab` changes nothing.
- **Least privilege**: every token, ServiceAccount and NetworkPolicy grants
  the minimum.
- **Secrets never in git or state**: `.secrets/`, `.env`, kubeconfigs,
  state files; secret values never in Terraform state.
- **Short-lived authority**: dynamic credentials and tokens in minutes; the
  seal agent's secret-id lives 24 h and rotates every 6 h.
- **Reproducible**: a colleague runs the demo from the docs alone.

---

## 7. Delivery plan (execute in order; each prompt ends with an execution log)

See `../00_roadmap.md` for the table. Each prompt adds its phases to
`scripts/phases.txt` (already listed in full by prompt 01) and must leave
`make lab` green up to its last phase.

---

## 8. Definition of done (whole project)

- `make crc-up && make lab` on a fresh CRC brings everything up; a second
  `make lab` reports every Terraform plan empty and every Ansible phase
  `changed=0` (exceptions only from `scripts/idempotency-allow.txt`).
- **Full rebuild proven**: `make crc-reset && make lab` green, timings per
  phase recorded in `docs/operations.md`.
- VSO syncs at least one `VaultStaticSecret` and one `VaultDynamicSecret`
  into `sg-workloads`; no workload pod has `VAULT_*` variables or a token.
- No Vault pod holds a seal token (`oc exec` + `env`, Secrets and mounts
  checked by `validate.yml`).
- Killing the active Vault pod: a standby serves within seconds.
- Restarting the seal agent: the cluster keeps serving; rotating twice
  leaves exactly one valid secret-id (`make rotation-proof`).
- Restarting the seal Vault: the cluster keeps serving; `make unseal`
  (one key) restores the chain.
- `make boundary` (19 checks), `make drift`, `make idempotency`,
  `make secret-scan`, `make validate`, `make identity-verify` all green.
- `prevent_destroy` + Vault policy protect the seal transit mount + key and
  `kv/` (proven by applying a deleted block: 403).
- UI passes the Playwright journeys and axe WCAG 2.1 AA with 0 violations
  at 1440×900 and 390×844.
- Docs let a colleague run the demo without asking you anything;
  `docs/substrate-contract.md` explains how to swap `terraform/infra/`.

## Execution log

Appended by each run: what was done, deviations and why, validation output.
