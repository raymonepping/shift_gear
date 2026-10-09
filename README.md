# Shift Gear

**Terraform builds the house. Ansible decorates it. Vault enforces the line. VSO delivers.**

Shift Gear is a production-grade reference platform for HashiCorp Vault Enterprise on OpenShift
Local (CRC). It deploys a three-node Vault HA cluster, a dedicated seal Vault, a seal agent that
holds no token on the cluster, and a full identity stack (OpenLDAP + Keycloak + OIDC/JWT/LDAP
auth). The Vault Secrets Operator syncs secrets into workload pods — no Vault token in any pod.

The substrate contract is the core idea: only `terraform/infra/` and `scripts/crc-*.sh` know
anything about CRC. Every other file consumes a six-field `cluster` output. Replace `infra` with a
module for ROSA, vSphere, or bare-metal OCP, and nothing else changes.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| CRC ≥ 2.45 (`crc` in PATH) | OpenShift Local 4.22 |
| Pull secret | From [console.redhat.com](https://console.redhat.com/openshift/create/local); save to `.secrets/crc/pull-secret.txt` |
| `VAULT_LICENSE` in `.env` | Your Vault Enterprise licence key |
| 8 vCPU / 24 GB RAM / 80 GB disk free | For the CRC VM |
| Terraform ≥ 1.9, Ansible-core 2.17, Helm 3, `oc`, `jq`, `curl` | All must be in PATH |

`.env` is read by `scripts/lab.sh` and `scripts/tf-run.sh`. Only `VAULT_LICENSE` is used.
`RHSM_*` keys in `.env` are kept for reference but are not consumed by any script — CRC
registers its own entitlement internally.

---

## Quick start

```sh
# Start OpenShift Local (first time — ~15 min)
make crc-up

# Build the full stack (~35–45 min first run)
make lab

# Second run: plans empty, Ansible changed=0 (idempotency proof)
make lab
```

---

## Phase list

Thirteen phases, interleaved Terraform and Ansible:

| # | Tool | Phase | What it owns |
|---|---|---|---|
| 1 | tf | infra | Substrate contract — discovers apps_domain + pod_cidr |
| 2 | tf | foundation | Namespaces, RBAC, NetworkPolicies, Routes, VSO Subscription |
| 3 | ansible | prepare | TLS certs, licence Secrets, CA ConfigMaps; waits for VSO CSV |
| 4 | tf | workloads | Helm releases, seal-agent, rotator, identity stack, VSO resources |
| 5 | ansible | seal-init | Init + unseal seal Vault; bootstrap policies; sg-tf-seal + sg-ansible-seal tokens |
| 6 | tf | seal | Transit mount + autounseal key + AppRole roles on seal Vault |
| 7 | ansible | agent | Secret-ids into Secrets; prove seal agent; rotator credentials |
| 8 | ansible | bootstrap | Cluster init, raft join, platform bootstrap policies; sg-tf-platform + sg-ansible-platform tokens |
| 9 | tf | platform | Vault namespace shift-gear, mounts, policies, token roles, audit |
| 10 | ansible | identity | LDAP seed, Keycloak realm, Vault OIDC/JWT/LDAP auth |
| 11 | ansible | configure | Kubernetes/AppRole/cert auth, DB connection, KV seeds, agent demo |
| 12 | ansible | ux | UI/API builds, evidence ConfigMap sync |
| 13 | ansible | validate | Read-only end-to-end proof → `.build/validation.json` |

---

## URLs (after `make lab`)

| Service | URL |
|---|---|
| Vault UI | `https://vault.apps-crc.testing` |
| Vault Seal UI | `https://vault-seal.apps-crc.testing` |
| Keycloak admin | `https://keycloak.apps-crc.testing/admin` |
| Shift Gear console | `https://sg-ui.apps-crc.testing` |

Sign in as `ada` (engineer) with password from `make identity-show-user PERSON=ada`.

---

## `make help`

```
make help
```

Key targets:

| Target | Description |
|---|---|
| `make lab` | Full 13-phase build + 3 gates |
| `make check` | Static gate: ShellCheck, tf fmt/validate, substrate grep |
| `make verify` | Full stack health (cluster operators, Vault HA, seal chain, VSO, gates) |
| `make drift` | Terraform plan + Ansible check-mode across all phases |
| `make idempotency` | Re-run all Ansible phases; require `changed=0` |
| `make boundary` | Prove tool boundary: 19 capabilities-self checks |
| `make rotation-proof` | Rotate seal agent secret-id twice; prove old=400/current=200/count=1 |
| `make identity-verify` | Every persona logs in and receives exactly their policies |
| `make wl-a-rotate` | Write new KV version; VSO syncs within ~30 s; workload-a rolls |
| `make vso-status` | VSO CRD sync status and workload pod states |
| `make down` / `make up` | Graceful scale-down / scale-up without losing PVCs |
| `make crc-reset && make lab` | Full destroy and rebuild from nothing |

---

## VSO demo (30 seconds)

```sh
make wl-a-rotate          # writes a new KV version
make vso-status           # watch VSO sync + workload-a rollout
```

The workload pod reads the new value from the mounted Secret — no Vault token, no restart trigger
in the pod spec.

---

## Documentation

| Document | Content |
|---|---|
| [Getting started](docs/getting-started.md) | First run, expected timings, first sign-in |
| [Architecture](docs/architecture.md) | Namespaces, seal chain, HA topology, VSO flow |
| [Substrate contract](docs/substrate-contract.md) | The `cluster` output, isolation rule, swapping the substrate |
| [Layers](docs/layers.md) | Per-phase: inputs, outputs, idempotency, resume |
| [Security model](docs/security-model.md) | Token boundary, demo vs. production, Vault state |
| [Operations](docs/operations.md) | Every `make` target, rotation, renewal, rebuild timings |
| [Demo guide](docs/demo-guide.md) | 5-min and 10-min run sheets for live demos |
| [Testing](docs/testing.md) | All gates and how to run them |
| [Decisions](docs/decisions.md) | Non-obvious choices with evidence |
| [Lessons learned](docs/lessons-learned.md) | What the build found |
| [Troubleshooting](docs/troubleshooting.md) | Symptom → cause → fix |
| [Enterprise mapping](docs/enterprise.md) | Lab mechanism → enterprise counterpart |

---

## Articles

The Shift Gear build is article 05 in a series:

| # | Lab | Article |
|---|---|---|
| 01 | multi_pass | [Contracts win](https://medium.com/@raymonepping) |
| 02 | red_pass | [Evidence wins](https://medium.com/@raymonepping) |
| 03 | both | [A Vault platform needs both answers](https://medium.com/@raymonepping) |
| 04 | golden_ticket | [Vault keeps the keys](https://medium.com/@raymonepping) |
| 05 | shift_gear | [Keep the dream alive](https://medium.com/@raymonepping) |

---

## Repository

```
https://github.com/raymonepping/shift_gear
```
