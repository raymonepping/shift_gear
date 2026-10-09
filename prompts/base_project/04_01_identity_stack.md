# Prompt 04 — Identity: OpenLDAP + Keycloak (Terraform deploys, Ansible configures)

---

## System Prompt Header

### 1. Persona & Role

You are a **Principal Platform & DevSecOps Engineer** specialising in
HashiCorp Enterprise architecture (Vault, Terraform), Red Hat OpenShift /
Kubernetes, and Ansible automation. Your output must exhibit:

- **Strict separation of concerns** — Terraform builds the house (anything
  with an API and a lifecycle: Kubernetes objects, Helm releases, Vault
  structure), Ansible decorates it (anything with an order and a moment:
  init, unseal, credentials, people, seeds, proof), the Vault Secrets
  Operator delivers secrets to workloads. Vault policy enforces the line.
- **Defensive, idempotent automation** — every script, playbook, and HCL
  block is re-runnable: a second `make lab` reports every plan empty and
  every Ansible phase `changed=0`.
- **Security by default** — zero hard-coded credentials, no secret value in
  Terraform state, short-lived tokens, mandatory CA verification (never
  `-tls-skip-verify`), least-privilege RBAC, NetworkPolicies and Vault
  policies.
- **Substrate agnosticism** — strict adherence to the `cluster` output
  contract; no substrate details (`crc`, `vfkit`, `api.crc.testing`,
  `apps-crc.testing`) outside `terraform/infra/` and `scripts/crc-*.sh`.

### 2. Target Audience

Tailor all deliverables, code comments, log output, and generated
documentation for three audiences:

| Audience | Focus | What they need |
| --- | --- | --- |
| **Enterprise Architects & Platform Engineers** | Layer separation, the tool boundary, substrate independence | See clearly *why* the design moves from CRC to bare-metal OCP or ROSA without changing a playbook, a policy or a VSO resource |
| **Operators running `make lab`** | Reproducibility, zero manual intervention, deterministic failures | Pre-flight validations, readable progress, explicit failure reasons (missing pull secret, VSO CSV not ready, stale Terraform outputs), the exact phase to resume |
| **AppDev & Security Teams** | Secret consumption without token exposure | Examples built on VSO resources and the Vault Agent sidecar, never direct API calls from application pods |

### 3. Operational Invariants (always enforced)

1. **Substrate isolation** — only `terraform/infra/` and `scripts/crc-*.sh`
   may reference the substrate. Everything else consumes the `cluster`
   contract (a grep in `make check` proves it).
2. **CSV gate** — never plan or apply a VSO resource until the Vault Secrets
   Operator CSV reports `phase=Succeeded`.
3. **Explicit namespaces** — set the Vault namespace explicitly on every
   task and resource; `tf-run.sh` unsets `VAULT_NAMESPACE`.
4. **Token hygiene** — each tool uses only its own bootstrap token on each
   Vault (`sg-tf-seal`, `sg-ansible-seal`, `sg-tf-platform`,
   `sg-ansible-platform`); root is break-glass only. **No seal token
   exists**: the cluster unseals through the seal agent. Agent tokens come
   from auto-auth and are checked for `renewable` and remaining TTL.
5. **No secret value in Terraform state** — licence, keys, init output,
   tokens, secret-ids and passwords are written by Ansible (`no_log`);
   Terraform references Secrets by name only.
6. **No blind copies** — consult `red_doors`, `golden_ticket` and
   `red_pass` for proven patterns, then adapt them to the Shift Gear
   contract. `00_01_shift_gear.md` wins on any conflict.

### 4. Execution Deliverables Standard

For every prompt executed under this specification:

- Provide production-ready, fully written files — no placeholders,
  no `TODO` comments, no truncated snippets.
- Append a clear **Execution Log** recording:
  1. What was created or configured.
  2. Deviations from predecessor projects and the architectural rationale.
  3. Validation steps executed to confirm convergence and zero-diff state.

---

## Context

Prompts 01–03 are done: the cluster is structured by `terraform/platform`;
`kv/` exists in namespace `shift-gear`; `make lab` is green through
`platform`.

**Terraform deploys, Ansible configures.** Terraform builds the identity
house (Deployments, Services, PVCs, Routes). Ansible decorates it: the
directory content, the Keycloak realm, the clients, the users, and Vault's
auth methods wired to the policies Terraform created.

Canonical references:

- `../red_doors/prompts/base_project/04_01_identity_stack.md`, its
  execution log and `../red_doors/deploy/identity/` (OpenLDAP built from
  Alpine, `slapd` on :1389 under the OpenShift UID, `{SSHA}` passwords,
  mdb on a PVC; Keycloak on OpenShift; the `givenName` mapper fix).
- `../golden_ticket/ansible/roles/identity_secrets`, `identity_stack`
  (Keycloak tasks), `vault_identity`, `identity_verify`, and
  `docs/lessons-learned.md` (Keycloak and Vault sections).

## Goal

People with LDAP group memberships sign in through Keycloak and get exactly
the Vault policy their group carries — through OIDC in a browser, through a
Keycloak JWT presented directly, and through LDAP. Vault is the OIDC client:
the console's sign-in *is* a Vault login.

## Deliverables

### Terraform (the house)

- `terraform/foundation/`: Route `keycloak.<apps_domain>` (reencrypt, the
  `iss` claim must equal this URL), BuildConfig + ImageStream for the
  OpenLDAP image (Alpine, arm64).
- `terraform/workloads/`: OpenLDAP Deployment + Service + PVC (base DN
  `dc=shiftgear,dc=local`); Keycloak Deployment + Service + PVC
  (`quay.io/keycloak/keycloak`, arm64, pinned by digest; dev-file storage on
  a PVC — justify), admin credentials from Secret `keycloak-admin` **by
  name** (Ansible creates it). Both `restricted-v2`, no `anyuid`.
  Keycloak's management port (9000) is not exposed by any Route.
- NetworkPolicy: Keycloak 8443 from the router and from `sg-vault`;
  OpenLDAP 1389/1636 from Keycloak and from `sg-vault` only.

### `ansible identity` (the decoration, `sg-ansible-platform`)

1. **Identity secrets in Vault KV** (golden_ticket `identity_secrets`):
   generate once (`lookup('password', '/dev/null length=32 …')`, `no_log`)
   and store under `kv/data/shift-gear/identity`: LDAP admin and read-only
   passwords, Keycloak admin password, client secrets, each person's
   password. Later runs read them back. No copy on disk. Then write the
   Kubernetes Secrets the Deployments reference (`openldap-admin`,
   `keycloak-admin`), changed only when the value changed.
2. **Directory** (idempotent LDIF through `kubernetes.core.k8s_exec` or a
   Job; compare before write):

   | User | Groups | Role in the demo |
   | --- | --- | --- |
   | `ada` | `engineers`, `staff` | primary demo user |
   | `ben` | `staff` | no engine access — wrong-identity demo |
   | `cleo` | `operators`, `staff` | operator: key rotation, leases |
   | `dirk` | `approvers`, `operators`, `staff` | second approver |
   | `finn` | `auditors` | read-only audit view |

   Group membership kept exactly as declared (remove stray members).
3. **Keycloak** (`community.general.keycloak_*`, reconciling): realm
   `shift-gear` — apply the realm **twice in the run that creates it**
   (Keycloak fills defaults on the first update; golden_ticket lesson);
   LDAP federation read-only with the default username/email/name mappers
   declared explicitly (passing `mappers:` replaces them), first name from
   `givenName`, group mapper with `multivalued: "true"` declared;
   confidential client `vault` with redirect URIs
   `https://vault.<apps_domain>/ui/vault/auth/oidc/oidc/callback`,
   `https://shiftgear.<apps_domain>/auth/callback` and
   `http://localhost:8250/oidc/callback` (CLI login — Red Doors 04), and a
   `groups` claim; public client `sg-cli` with direct grants for the
   verification tests only. The federation task is skipped in check mode
   with a comment (D14; lesson 26).
4. **Vault auth** (Ansible owns auth methods — §4): `oidc/` (discovery
   `https://keycloak.<apps_domain>/realms/shift-gear`, CA = the ingress CA
   from the contract), role `visitor` (`groups_claim=groups`,
   `user_claim=preferred_username`, `token_ttl=30m`); `jwt/` for direct
   Keycloak tokens (a JWT/OIDC mount with a client id refuses JWT logins);
   `ldap/` against OpenLDAP. External groups, one per mount (an external
   group carries one alias): `engineers` → `sg-engineer`, `operators` →
   `sg-operator`, `approvers` → `sg-approver`, `auditors` → `sg-auditor`.
   **Before wiring, assert those policies exist** (Terraform built them);
   refuse to decorate otherwise.
5. Every task sets the Vault namespace explicitly (lesson 16); `uri` tasks
   with `failed_when` on unexpected status; secrets only in headers/bodies,
   never in URLs (lesson 30).

### `ansible/identity-verify.yml` (`make identity-verify`)

Port golden_ticket's `identity_verify`: every person logs in through
Keycloak (OIDC/JWT) and through LDAP and receives **exactly** their
policies (ask `token/lookup-self` — the login response leaves
`identity_policies` empty); `ada` reads KV, `finn` is refused a write,
`ben` gets no engine access. Report rows to
`.build/identity-verify.json` (non-secret). `make identity-show-user
PERSON=<name>` prints one person's password from Vault (explicit, lab-only).

## Validation

```sh
make lab && make lab                # second run: identity changed=0
make identity-verify                # every row as expected
vault login -method=oidc -namespace=shift-gear role=visitor   # ada → sg-engineer (browser)
# check mode on identity reports changed=0 (federation skipped by design)
# from a pod in sg-workloads: OpenLDAP and Keycloak are refused (NetworkPolicy)
```

## Out of scope

Kubernetes/AppRole/cert auth, KV seeds, the DB connection (prompts 05–06).
The console's sign-in screens (frontend prompts).

## Execution log

Appended by each run: what was done, deviations and why, validation output.
