# Security model

---

## Overview

Shift Gear applies defence-in-depth at four layers:

1. **Vault policy** — what each bootstrap token may read/write/create.
2. **Kubernetes RBAC and NetworkPolicy** — what each pod may reach.
3. **mTLS** — the seal agent's listener requires client + server certificates.
4. **Secret hygiene** — no secret value in Terraform state; no token in any workload pod.

---

## Secret boundary per tool

| Secret | Where it lives | Tool that writes it | Tool that reads it |
|---|---|---|---|
| `VAULT_LICENSE` | `.env` (local, gitignored) | Human | ansible prepare |
| Vault init keys | `.secrets/` (local, gitignored) | ansible seal-init, bootstrap | break-glass only |
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

**Secret values are never in Terraform state.** Terraform declares structure (mount paths, role
names, policy text); Ansible writes values (`no_log: true`).

---

## The four bootstrap tokens

| Token | Created by | Used by | Capabilities (summary) |
|---|---|---|---|
| `sg-tf-seal` | ansible seal-init | tf seal | `sys/mounts`, `transit/keys`, `auth/approle/role` |
| `sg-ansible-seal` | ansible seal-init | ansible agent | `auth/approle/role/*/secret-id`, `auth/approle/role/*/role-id` |
| `sg-tf-platform` | ansible bootstrap | tf platform | `sys/mounts`, `sys/policies/acl`, `sys/auth` (read), token roles, audit |
| `sg-ansible-platform` | ansible bootstrap | ansible configure, identity, ux | `sys/auth`, `kv/data`, `database/config`, `pki-int`, identity |

Root token: **break-glass only**. It is written to `.secrets/` with mode 0600 and is not
used by any script in normal operation. Rotation: `vault token create -orphan -policy=root`
from the break-glass token, then revoke the old root.

Each token has a 72-hour TTL and is renewable. `lab.sh` renews them before each run if
less than 24 hours remain.

---

## Seal agent

The seal agent authenticates to the seal Vault with AppRole:

- **CIDR restriction:** the AppRole role has `secret_id_bound_cidrs` set to the pod CIDR
  (`10.217.0.0/22` on CRC, discovered from `pod_cidr` contract field). A secret-id generated
  outside the cluster cannot be used.
- **NetworkPolicy:** `sg-vault-seal` namespace has a `deny-all` default with an explicit
  allow from `sg-vault` pods. Nothing else can reach the seal Vault directly.
- **mTLS:** the seal agent's listener requires client certificates signed by the project CA.
  Vault pods present their TLS certificate as a client certificate.
- **Rotation:** the rotator CronJob runs every 24 hours, generates a new secret-id, writes it
  to the `seal-agent-approle` Secret, and kills the seal-agent pod to force a reload.
  `make rotation-proof` proves the old secret-id returns 400 and the new one returns 200.

**No seal token on the cluster.** The cluster Vault pods unseal themselves via the transit
seal stanza: `seal { type="transit" }` in their Helm values. The seal agent never holds
a cluster Vault token — it only authenticates to the seal Vault.

---

## VSO: workloads hold nothing

The Vault Secrets Operator authenticates using **Kubernetes auth** with the projected SA token of
the `vso-workloads` service account. No Vault token is stored in any Secret, ConfigMap,
or environment variable.

The resulting Kubernetes `Secret` objects (`app-config`, `db-creds`) are mounted read-only into
the workload pods. The pods do not have a Vault address in their environment.

`make verify` checks that no pod in `sg-workloads` or `sg-app` has a `VAULT_*` environment
variable.

---

## Vault Agent sidecar

The `agent-demo` pod uses Vault Agent (init container + sidecar) with Kubernetes auth. The
pod SA token is the credential. The rendered file (`/vault/secrets/demo-secret`) is shared
via an `emptyDir` volume. No Vault token is present in the application container's environment.

---

## NetworkPolicies

All namespaces have a `default-deny` ingress policy. The explicit allow rules:

| Namespace | Allow from | Port | Purpose |
|---|---|---|---|
| `sg-vault-seal` | `sg-vault` (label: `app.kubernetes.io/name=vault`) | 8200, 8201 | Transit seal + raft |
| `sg-vault-seal` | `sg-vault-seal` (label: `app=seal-agent`) | 8200 | Agent AppRole |
| `sg-vault` | Ingress controller namespace | 8200 | Route (UI + API) |
| `sg-vault` | `sg-workloads`, `sg-app` | 8200 | VSO, agent-demo |
| `sg-vault` | `sg-vault` | 8201 | Raft peer traffic |
| `sg-identity` | `sg-vault` | 1389 | LDAP auth from Vault |

---

## Demo-grade vs. production

| Aspect | This lab | Production change |
|---|---|---|
| Shamir seal on seal Vault | 1 share, threshold 1 | ≥ 5 shares, threshold 3; auto-unseal with HSM or KMS |
| CA | Project-local CA (scripts/tls.sh) | Public CA or enterprise PKI |
| Vault HA | 3 nodes, Raft, no storage HA on PVC | Integrated Storage on persistent storage with replication |
| LDAP | Single OpenLDAP pod, no replication | Active Directory or LDAP cluster |
| Token TTLs | 72 h renewable | Short-lived; machine identity via OIDC + Vault Agent |
| Init key storage | `.secrets/` local | Vault auto-unseal + operator custody (quorum) |
| Bootstrap tokens | Static, written to disk | Dynamic credentials via Vault's own OIDC provider or HCP Vault |
| State files | Local `.secrets/terraform/` | HCP Terraform workspaces with encryption |

---

## Audit

Vault audit is enabled at two devices:

1. **File** — writes to `/vault/audit/audit.log` on a PVC in each pod.
2. **Socket** — Ansible configure enables this after the KV seeds are in place.

If both audit devices fail, Vault blocks all writes. This is intentional (Vault's default
behaviour) and documents the production posture.
