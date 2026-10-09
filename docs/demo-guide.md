# Demo guide

Two run sheets: a 10-minute deep dive and a 5-minute show. Both assume `make lab` has
already converged and `make verify` is green. Open a browser tab on
`https://vault.apps-crc.testing` and `https://sg-ui.apps-crc.testing` before starting.

---

## 10-minute run sheet

### 0:00 — Sign in as `ada`

```sh
make identity-show-user PERSON=ada
```

Open `https://vault.apps-crc.testing`, click **Sign in with OIDC**. Enter `ada` and the
password. You land on `ada`'s token with policies `sg-engineer` and `sg-staff`.

**What to say:** Vault is on OpenShift. The URL is a Route — TLS passthrough from the
ingress controller to the Vault pod. No load balancer required.

### 1:00 — Fleet page

Open `https://sg-ui.apps-crc.testing`. The Fleet page appears.

**What to say:** The console pulls live data from the OpenShift API (through the Shift Gear
API's BFF). The tiles show pod count, CPU and memory totals for the workloads Terraform root.
Every number traces back to the `terraform/workloads/` output.

### 2:30 — Layers page

Click **Layers**.

**What to say:** Thirteen phases — five Terraform roots, eight Ansible playbooks, in order.
The gates below the phases show idempotency, secret-scan, boundary, and drift. Each phase has
an expand arrow showing what it owns and its last duration.

### 4:00 — Static secret rotation

In the terminal:

```sh
make wl-a-rotate
```

Back in the Shift Gear console, click **Operator** and watch the `app-config` `VaultStaticSecret`
`lastSyncTime` update. Switch to the **Fleet** page and watch `workload-a` roll (one new pod
replaces the old one within ~30 seconds).

**What to say:** No token in the workload pod. The Vault Secrets Operator authenticated with
Kubernetes auth (projected SA token). The pod sees a Kubernetes `Secret` — it has no Vault
address in its environment.

### 5:30 — Dynamic credential revoked

```sh
# Get the current lease ID
make vso-status
```

Revoke the lease from the Vault UI (navigate to `database/creds/demo-reader` → Leases →
revoke). Switch back to the console **Operator** page. Within the `renewalPercent` cycle
(~60 s) VSO requests a new credential, the `db-creds` Secret is updated, and `workload-b`
reads the new username without restarting.

**What to say:** Dynamic credentials have a TTL. VSO renews them at 80% of TTL. Revoking
forces an immediate refresh — the workload continues with a new credential.

### 7:00 — Vault HA failover

```sh
oc -n sg-vault delete pod vault-0
```

Click the **Cluster** page in the console. The active node icon moves from `vault-0` to
`vault-1` (or `vault-2`) within a few seconds.

```sh
make verify
```

**What to say:** Raft elects a new leader. The transit seal is on the seal Vault — killing
a cluster node does not require any unseal action. The seal chain is unaffected.

### 8:30 — Seal chain

```sh
oc -n sg-vault-seal delete pod -l app=seal-agent
```

The seal-agent pod restarts, re-authenticates with AppRole, and is ready within ~10 seconds.

**What to say:** The seal agent holds the AppRole secret-id, not a Vault token. The cluster
Vault never had the secret-id. If the agent pod is deleted, the cluster Vault is unaffected —
it already has the transit key lease. The agent's job is to handle rotation, not to hold
an ongoing credential.

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
| 0:30 | Fleet page | Live tile data from the OpenShift API |
| 1:00 | `make wl-a-rotate` | Watch app-config sync and workload-a roll |
| 2:00 | Revoke dynamic credential | VSO fetches new one; workload-b continues |
| 3:00 | Kill vault-0 pod | Cluster page shows new active leader |
| 4:00 | `make boundary` | 19/19; Terraform cannot mint a secret-id |
| 4:30 | `make verify` | All ✓ |

---

## Personas

| User | Groups | Vault policies | Auth method |
|---|---|---|---|
| `ada` | engineers, staff | `sg-engineer`, `sg-staff` | OIDC (Keycloak), LDAP |
| `ben` | staff | `sg-staff` | OIDC, LDAP |
| `cleo` | operators, staff | `sg-operator`, `sg-staff` | OIDC, LDAP |
| `dirk` | approvers, operators, staff | `sg-approver`, `sg-operator`, `sg-staff` | OIDC, LDAP |
| `finn` | auditors | `sg-auditor` | OIDC, LDAP |

Sign in as any of them: `make identity-show-user PERSON=<name>`.

---

## What to say when it goes wrong

| Problem during demo | Say |
|---|---|
| Vault UI unreachable | "CRC is a single VM — let me check if it went to sleep." `make crc-up && make up` |
| VSO not syncing | "This is the CSV gate in action — the operator isn't ready. `make vso-status`" |
| `make verify` shows ✗ on gate | "The gate file is stale. `make validate` regenerates it." |
| `make boundary` fails | "A token was rotated and the file is stale. `make seal-init && make bootstrap`" |
