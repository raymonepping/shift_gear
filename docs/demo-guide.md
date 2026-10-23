# Demo guide

Two run sheets: a 10-minute deep dive and a 5-minute show. Both assume `make lab` has
already converged and `make verify` is green.

Before starting: run `make trust` so the browser accepts the project CA without warnings.
Open a tab on `https://vault.apps-crc.testing` and `https://shiftgear.apps-crc.testing`.

---

## 10-minute run sheet

### 0:00 — Sign in as `ada`

```sh
make identity-show-user PERSON=ada
```

Open `https://vault.apps-crc.testing`, click **Sign in with OIDC**. Enter `ada` and the
password. You land on `ada`'s token with the `sg-engineer` identity policy. The
`staff` directory group carries no policy.

**What to say:** Vault is on OpenShift. The URL is a Route — TLS passthrough from the
ingress controller to the Vault pod. No load balancer required.

### 1:00 — Fleet page

Open `https://shiftgear.apps-crc.testing`. The Fleet page appears.

**What to say:** The console reads the evidence snapshot collected by `scripts/evidence.py` and published by `make ux`. The tiles show the observed pod and resource totals; they do not poll the OpenShift API directly.

### 2:30 — Layers page

Click **Layers**.

**What to say:** Thirteen phases — five Terraform roots, eight Ansible playbooks, in order.
The gates below the phases show idempotency, drift, secret-scan, and validation. Each phase has
an expand arrow showing what it owns and its last duration.

### 4:00 — Static secret rotation

In the terminal:

```sh
make wl-a-rotate
```

Back in the Shift Gear console, click **Operator** and watch the `app-config` `VaultStaticSecret`
`lastSyncTime` after running `make ux` to publish a new snapshot. Fleet and Operator views show observed state; use `make vso-status` for current cluster status.

**What to say:** No token in the workload pod. The Vault Secrets Operator authenticated with
Kubernetes auth (projected SA token). The pod sees a Kubernetes `Secret` — it has no Vault
address in its environment.

### 5:30 — Dynamic credential revoked

```sh
# Get the current lease ID
make vso-status
```

Run `bash scenarios/07_dynamic_credential_revoked/run.sh` to revoke the actual
lease from the `VaultDynamicSecret` status and check both credential replacement
and old PostgreSQL role removal. The next renewal is scheduled at 67% of a
five-minute lease; the proof allows 240 seconds. Run `make ux` afterwards to
publish the observed state on Operator.

**What to say:** Dynamic credentials have a TTL. Revocation removes the old
PostgreSQL role. VSO discovers it on reconciliation and fetches a new credential,
then rolls workload-b through its configured restart target.

### 7:00 — Vault HA failover

```sh
bash scenarios/01_kill_active/run.sh
```

Run `make ux`, then click **Cluster**. The refreshed snapshot shows the newly elected leader. The script chooses the
actual active pod; deleting a fixed pod name could merely delete a standby.

```sh
make verify
```

**What to say:** Raft elects a new leader. The transit seal is on the seal Vault — killing
a cluster node does not require any unseal action. The seal chain is unaffected.

### 8:30 — Seal chain

```sh
oc -n sg-vault-seal delete pod -l app.kubernetes.io/name=seal-agent
```

The seal-agent pod restarts, re-authenticates with AppRole, and authenticates without operator intervention.

**What to say:** The seal agent authenticates with AppRole and keeps its short-lived token in memory. Cluster pods carry no seal-Vault token. Restarting the agent does not reseal an already-unsealed cluster; new unseal operations need the agent available.

### 9:30 — Layers gate: boundary

```sh
make boundary
```

Output: 19/19 checks passed.

**What to say:** Each of the four bootstrap tokens is asked what it can do on paths it must
and must not touch. Terraform cannot mint a secret-id. Ansible cannot create a mount. The
boundary is enforced by Vault policy — not by convention.

---

## 5-minute run sheet

| Time | Action | One-liner |
|---|---|---|
| 0:00 | Sign in as `ada` via OIDC | Vault on OpenShift; Route + TLS passthrough |
| 0:30 | Fleet page | Observed tile data from the latest evidence snapshot |
| 1:00 | `make wl-a-rotate` | Watch app-config sync and workload-a roll |
| 2:00 | Revoke dynamic credential | VSO fetches new one; workload-b continues |
| 3:00 | Kill vault-0 pod | Cluster page shows new active leader |
| 4:00 | `make boundary` | 19/19; Terraform cannot mint a secret-id |
| 4:30 | `make verify` | All ✓ |

---

## Personas

| User | Groups | Vault policies | Auth method |
|---|---|---|---|
| `ada` | engineers, staff | `sg-engineer` | OIDC (Keycloak), LDAP |
| `ben` | staff | none (`staff` is a grouping group) | OIDC, LDAP |
| `cleo` | operators, staff | `sg-operator` | OIDC, LDAP |
| `dirk` | approvers, operators, staff | `sg-approver`, `sg-operator` | OIDC, LDAP |
| `finn` | auditors | `sg-auditor` | OIDC, LDAP |

Sign in as any of them: `make identity-show-user PERSON=<name>`.

---

## What to say when it goes wrong

| Problem during demo | Say |
|---|---|
| Vault UI unreachable | "CRC is a single VM — let me check if it went to sleep." `make crc-up && make up` |
| VSO not syncing | "This is the CSV gate in action — the operator isn't ready. `make vso-status`" |
| `make verify` shows ✗ on a gate | Inspect the named gate’s output; run its own target. `make validate` only regenerates validation. |
| `make boundary` fails | "A token was rotated and the file is stale. `make seal-init && make bootstrap`" |

## Scenario inventory

| Scenario | What the script exercises |
| --- | --- |
| 01 | Active pod deletion and unsealed rejoin |
| 02 | Seal-agent restart with cluster health probes |
| 03 | Two rotator Jobs and secret-id lookup/list |
| 04 | Seal-Vault restart and manual unseal |
| 05 | Full down/up including VM stop/start |
| 06 | KV source rotation, Secret sync and workload-a rollout |
| 07 | Dynamic credential replacement and old-role removal |
| 08 | Four reversible drift mutations with detection and restoration checks |
| 09 | Hand-edit app-config; VSO restored the Vault value in 6 s in the proof run |

Run results and timings from 2026-10-09 are recorded in roadmap 03_01.

## Audit page moment

Sign in as finn and open Audit. Signing in generates audited requests, and the
page reads the collector live through the BFF. It shows request metadata and
the names of HMAC-protected fields, not those secret values. Its buffer and
counters reset on collector restart. Every signed-in persona can read this view.
