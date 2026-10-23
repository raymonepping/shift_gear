# Shift Gear

**Terraform builds the house. Ansible decorates it. Vault enforces the line. VSO delivers.**

Shift Gear is a local reference platform for HashiCorp Vault Enterprise on OpenShift
Local (CRC). It deploys a three-node Vault HA cluster, a dedicated seal Vault, a seal agent that
keeps its short-lived seal-Vault token in memory, and a full identity stack (OpenLDAP + Keycloak + OIDC/JWT/LDAP
auth). The Vault Secrets Operator syncs secrets into workload pods — no Vault token in the VSO application containers.

The substrate contract is the core idea: only `terraform/infra/` and `scripts/crc-*.sh` know
anything about CRC. The automation above infra consumes a six-field `cluster` output. Replace `infra` with a
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

# Build the full stack (first-run timing awaits the fresh-VM proof)
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

## URLs (CRC example after `make lab`)

| Service | URL |
|---|---|
| Vault UI | `https://vault.apps-crc.testing` |
| Vault Seal UI | `https://vault-seal.apps-crc.testing` |
| Keycloak login | `https://keycloak.apps-crc.testing/` (redirects to `https://shiftgear.apps-crc.testing/signin`) |
| Keycloak admin | `https://keycloak.apps-crc.testing/admin` |
| Shift Gear console | `https://shiftgear.apps-crc.testing` |

Trust the project CA for the passthrough Vault Routes. Keycloak and the console use the router certificate, whose CA is fetched separately to `.secrets/kube/ingress-ca.pem`:

```sh
make trust
```

Sign in as `ada` (engineer) with password from `make identity-show-user PERSON=ada`.

---

## `make help`

```
make help
```

Key targets:

| Target | Description |
|---|---|
| `make lab-times` | Last measured phase and gate timings |
| `make ui-check` | Nuxt type-check and ESLint |
| `make ui-test` | Both Playwright projects, journeys and axe accessibility scans |
| `make ui-test-failover` / `make ui-screens` | Separate failover journey / screenshot set |
| `make lab` | Full 13-phase build + 3 gates |
| `make check` | Static gate: ShellCheck, tf fmt/validate, substrate grep |
| `make verify` | Full stack health (cluster operators, Vault HA, seal chain, VSO, gates) |
| `make drift` | Terraform plan + Ansible check-mode across all phases |
| `make idempotency` | Re-run all Ansible phases; require `changed=0` |
| `make boundary` | Prove tool boundary: 19 capabilities-self checks |
| `make rotation-proof` | Rotate seal agent secret-id twice; prove previous ID absent/current lookup=200/count=1 |
| `make identity-verify` | Every persona logs in and receives exactly their policies |
| `make wl-a-rotate` | Write new KV version; VSO syncs within ~30 s; workload-a rolls |
| `make vso-status` | VSO CRD sync status and workload pod states |
| `make trust` / `make untrust` | Add / remove the lab CA from the macOS System keychain |
| `make down` / `make up` | Graceful scale-down / scale-up without losing PVCs |
| `make reset`, then `make crc-reset && make lab` | Destructive fresh-VM rebuild after generated state is archived; approval required |

---

## VSO demo (30 seconds)

```sh
make wl-a-rotate          # writes a new KV version
make vso-status           # watch VSO sync + workload-a rollout
```

The workload pod reads the new value from the mounted Secret without a Vault token. VSO uses `rolloutRestartTargets` to restart workload-a after a source change.

---

## Documentation

| Document | Content |
|---|---|
| [Project analysis](docs/project-analysis.md) | Current architecture, evidence baseline, source-confirmed gaps and strengthening opportunities |
| [MoSCoW roadmap](docs/roadmap.md) | Must, Should, Could and Wont priorities, dependencies, increments and exit gates |
| [PRD](docs/PRD.md) | Product/project requirements, user journeys, acceptance criteria and release verification |
| [Policy and ownership explorer](docs/policy-ownership-explorer.md) | Read-only declared ownership, expected capabilities and publication provenance |
| [Runtime observation](docs/runtime-observation.md) | Bounded live reads, source states and narrow observation permissions |
| [Vault component proofs](docs/vault-component-proofs.md) | Dedicated PKI/Transit lifecycle tests and destruction guards |
| [Dependency operations](docs/dependency-operations.md) | Lockfiles, image identity, operator approval, snapshots and upgrade/rollback |
| [Selected Should progress](docs/should-progress.md) | S01/S02/S05/S06 implementation and observed acceptance |
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

## Console pages and scenarios

The console has Sign-in, Fleet, Layers, Engines, Pods, Routes, Operator,
Ansible, Agent, Audit and Cluster pages. Cluster, pod and VSO views read
snapshots published by `make ux`; the Audit page reads the collector live.

| Scenario | Purpose |
| --- | --- |
| 01 | Delete the active Vault pod and observe a new leader and unsealed rejoin |
| 02 | Restart the seal agent while cluster requests continue |
| 03 | Run the rotator twice and inspect secret-id lookup/list |
| 04 | Restart the Shamir seal Vault, then unseal it |
| 05 | Stop and restart the complete lab, including the CRC VM |
| 06 | Change the Vault KV source, observe VSO sync and workload-a rollout |
| 07 | Revoke or replace the dynamic credential and check the old PostgreSQL role |
| 08 | Four reversible drift mutations with detection and restoration checks |
| 09 | Hand-edit a VSO-owned Secret; VSO restored the Vault value in 6 s |

Results and limitations belong in [Testing](docs/testing.md) and the roadmap
execution log; the presence of a script does not mean its proof has passed.

Must implementation and current verification: [delivery record](docs/must-progress.md), [credential operations](docs/credential-operations.md), [session contract](docs/session-contract.md), [ownership](docs/ownership.md).

C02/C03 extension: [metrics and retained audit](docs/observability.md), [isolated Agent database delivery](docs/agent-database-consumer.md) and [acceptance status](docs/c02-c03-progress.md). Other unfinished roadmap items remain deferred.
