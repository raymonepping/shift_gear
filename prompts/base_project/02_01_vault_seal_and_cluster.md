# Prompt 02 — Seal Vault, seal agent, and 3-node Vault Enterprise auto-unsealed through the agent

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

Prompt 01 is done: CRC runs, the `cluster` contract exists, the five
namespaces exist, `make lab` runs `infra` + `foundation`.

This prompt builds the seal chain golden_ticket built on VMs, on OpenShift:

```text
.secrets/seal-init.json (Shamir 1/1)                         operator-held root of trust
        │ make unseal
sg-vault-seal: vault-seal-0 ── transit/keys/autounseal       terraform/seal
        ▲  AppRole seal-autounseal (CIDR: cluster pod network; NetworkPolicy: agent pod only)
sg-vault-seal: seal-agent   Vault Agent, api_proxy force, mTLS :8200   ansible/agent.yml
        ▲  each Vault pod's own client certificate; NetworkPolicy: sg-vault Vault pods only
sg-vault: vault-0..2   seal "transit" → seal-agent; no seal token anywhere   ansible/bootstrap.yml
```

Canonical references:

- `../golden_ticket/ansible/roles/seal_agent/` (agent config, rotator,
  secret-id checks), `../golden_ticket/terraform/seal/`,
  `../golden_ticket/policies/` (`autounseal.hcl`, `seal-rotator.hcl`,
  `bootstrap/*.hcl`), `../golden_ticket/ansible/roles/vault_bootstrap/`
  (`seal.yml`, `cluster.yml`, `tokens.yml`), `docs/decisions.md` D8, D11.
- `../red_doors/prompts/base_project/02_01_vault_seal_and_cluster.md` and
  its execution log: Helm values on OpenShift, `$(POD_IP)` for `api_addr`
  (lesson 10), `wait-for-seal-vault` (lesson 11), `OnDelete` + controlled
  roll, single-node affinity override, arm64 digest.

## Goal

From `make lab`: a seal Vault, a seal agent with rotating AppRole
credentials, and a 3-node Vault Enterprise cluster that auto-unseals through
the agent, with the four bootstrap tokens issued and no seal token on any
Vault pod. The phases this prompt delivers:

```text
ansible prepare · tf workloads · ansible seal-init · tf seal · ansible agent · ansible bootstrap
```

## Deliverables

### `terraform/foundation/` additions

- Routes: `vault.<apps_domain>` → `vault-active` (passthrough) and
  `vault-seal.<apps_domain>` → `vault-seal` (passthrough, operator and
  automation access). Hostnames derived from `apps_domain`.
- **Vault Secrets Operator** `Subscription` (certified, `openshift-operators`,
  channel `stable`) as a `kubernetes_manifest`. Terraform owns its
  existence; Ansible `prepare` waits for the CSV (lesson 18).
- ServiceAccounts `seal-agent` and `seal-rotator` in `sg-vault-seal`; a
  `Role` + `RoleBinding` that lets `seal-rotator` `get`/`patch` **only**
  Secret `seal-agent-approle` (`resourceNames`).
- NetworkPolicies:
  - `sg-vault-seal/seal-agent`: ingress on 8200 only from pods labelled
    `app.kubernetes.io/name=vault` in `sg-vault`.
  - `sg-vault-seal/vault-seal`: ingress on 8200 from the `seal-agent` and
    `seal-rotator` pods, and from the router
    (`policy-group.network.openshift.io/ingress: ""`) for the passthrough
    Route.
  - `sg-vault/vault`: 8200/8201 between Vault pods, 8200 from the router
    and from `sg-workloads`, `sg-app`, `openshift-operators` (VSO).
  Prove each policy from a throwaway pod in the log (allowed and refused).

### `ansible prepare` (Secrets with values — never Terraform)

- `scripts/tls.sh` (called by the play; idempotent): project CA
  (`.secrets/tls/ca.{pem,key}`), certificates with **`notBefore` one hour
  back** (lesson 23) and **`serverAuth,clientAuth`** (lesson 24) for:
  - Vault: `vault.sg-vault.svc`, `*.vault-internal`,
    `*.vault-internal.sg-vault.svc.cluster.local`,
    `vault-active.sg-vault.svc`, `vault.<apps_domain>`, `127.0.0.1`.
  - seal Vault: `vault-seal.sg-vault-seal.svc`,
    `vault-seal-0.vault-seal-internal`, `vault-seal.<apps_domain>`.
  - seal agent: `seal-agent.sg-vault-seal.svc`.
  Renews any certificate expiring within 30 days. Hostnames from the
  contract (lesson 19).
- Kubernetes Secrets (`kubernetes.core.k8s`, `no_log`): `vault-tls`,
  `vault-seal-tls`, `seal-agent-tls`, `vault-license` (in `sg-vault-seal`
  and `sg-vault`, from `VAULT_LICENSE`), and ConfigMap `sg-ca` (public CA)
  in every namespace that talks to Vault.
- Wait for the VSO CSV `Succeeded` (fail loudly with the CSV name and phase
  on timeout).
- Changed only when a certificate or Secret really changes (compare
  fingerprints / data hashes first).

### `terraform/workloads/` (Helm + Deployments; Secrets by name only)

- Image: `docker.io/hashicorp/vault-enterprise:2.1.0-ent` pinned by digest,
  arm64 manifest verified (`oc image info --show-multiarch`), recorded.
- `helm_release.vault_seal` (`deploy/vault-seal/values.yaml`): standalone,
  Raft on a PVC, 1 replica, injector off, UI off, `global.openshift: true`,
  100m / 256Mi, licence via `VAULT_LICENSE_PATH`, TLS listener from
  `vault-seal-tls`. Readiness accepts sealed and uninitialised
  (`sealedcode=204&uninitcode=204`), so the release can wait.
- `seal-agent` Deployment (`deploy/seal-agent/`, 1 replica, SA
  `seal-agent`, `restricted-v2`): `vault agent` with
  - `auto_auth { method "approle" { role_id_file_path, secret_id_file_path,
    remove_secret_id_file_after_reading = false } }` reading Secret
    `seal-agent-approle` (created by Ansible `agent`);
  - `api_proxy { use_auto_auth_token = "force" }`;
  - `listener "tcp" { address = "0.0.0.0:8200", tls_cert_file, tls_key_file,
    tls_client_ca_file, tls_require_and_verify_client_cert = true }`;
  - `vault { address = "https://vault-seal.sg-vault-seal.svc:8200", ca_cert }`.
  Service `seal-agent`. `wait = false` (it cannot authenticate before the
  `agent` phase). Port the agent HCL from golden_ticket's role.
- `seal-rotator` CronJob (SA `seal-rotator`): schedule `0 */6 * * *`,
  `startingDeadlineSeconds: 21600` (a slot missed while CRC was stopped runs
  once after resume — the CronJob equivalent of golden_ticket's
  `Persistent=true`), `concurrencyPolicy: Forbid`. It logs in with the
  `seal-rotator` AppRole (its credentials in Secret `seal-rotator-approle`),
  mints a new secret-id for `seal-autounseal`, patches Secret
  `seal-agent-approle`, then destroys the previous secret-id by accessor.
  Port the logic from golden_ticket's rotator script.
- `helm_release.vault` (`deploy/vault/values.yaml`): HA, 3 replicas, Raft on
  PVCs, injector off, UI on, `global.openshift: true`; affinity overridden
  for the single-node cluster (document why); `api_addr` from `$(POD_IP)`
  (lesson 10; check `helm template` for a literal `$(`); `OnDelete` update
  strategy. Seal stanza:

  ```hcl
  seal "transit" {
    address         = "https://seal-agent.sg-vault-seal.svc:8200"
    key_name        = "autounseal"
    mount_path      = "transit/"
    tls_ca_cert     = "/vault/userconfig/sg-ca/ca.pem"
    tls_client_cert = "/vault/userconfig/vault-tls/tls.crt"
    tls_client_key  = "/vault/userconfig/vault-tls/tls.key"
    tls_server_name = "seal-agent.sg-vault-seal.svc"
    # no token: the agent forces its own on every request
  }
  ```

  Verify on the running system that Vault starts without `VAULT_TOKEN` and
  without a `token` field (golden_ticket used a placeholder token the agent
  overwrites; use whichever the 2.1.0 binary requires and record it).
  `wait-for-seal-vault` init container (lesson 11) polls the **agent**
  (`/v1/sys/health` through mTLS with the pod's certificate) until the seal
  Vault behind it answers unsealed. Readiness:
  `/v1/sys/health?standbyok&perfstandbyok&sealedcode=204&uninitcode=204`.
  `wait = false`.

### `ansible seal-init`

Port golden_ticket's `vault_bootstrap/seal.yml`: wait for `vault-seal-0`;
init with **1 share / threshold 1** if uninitialised (demo grade, single
operator — comment why), result to `.secrets/seal-init.json` (`0600`,
`no_log`); unseal if sealed; write the seal bootstrap policies
`sg-tf-seal` and `sg-ansible-seal` (`policies/bootstrap/`) and their token
roles with the root token; issue the two tokens to
`.secrets/tokens/{tf-seal,ansible-seal}` (periodic orphan, 24 h, re-issued
when invalid). Root is not used again by routine phases. `make unseal`
(`ansible/unseal.yml`) unseals the seal Vault with its one key.

### `terraform/seal` (Vault provider, `sg-tf-seal`)

Port `../golden_ticket/terraform/seal/`: `vault_mount.transit` and
`vault_transit_secret_backend_key.autounseal` (non-exportable,
`deletion_allowed = false`), both `prevent_destroy` (lesson 22) **and**
`sg-tf-seal` has no `delete` on `sys/mounts/transit` or the key (D11);
policies `autounseal` (`update` on `transit/encrypt/autounseal` and
`transit/decrypt/autounseal` only) and `seal-rotator`; AppRole mount and
roles `seal-autounseal` (secret-id TTL 24 h, token TTL 1 h, lockout bounded
— lesson 3) and `seal-rotator` (may only mint/destroy secret-ids of
`seal-autounseal`). `secret_id_bound_cidrs` / `token_bound_cidrs` =
`cluster.pod_cidr` written in canonical form (D8). Document the trade-off:
pod IPs are not stable, so the CIDR is the cluster network and the
per-pod restriction is the NetworkPolicy. `tests/` with mock providers
(CIDRs come from the contract; the key is non-exportable and undeletable).

### `ansible agent` (`sg-ansible-seal`)

Port golden_ticket's `seal_agent` role: read the role-ids; check whether
the secret-ids currently in Secrets `seal-agent-approle` and
`seal-rotator-approle` still exist in Vault and mint new ones only when they
do not (so a second run is `changed=0` and a lab stopped beyond 24 h
recovers); write the Secrets (`no_log`); restart the agent only when its
credentials changed; wait until the agent holds a token; **prove the agent
from a Vault pod's network position** with that pod's certificate
(`oc exec` into the init container is not possible, so run a one-shot pod
in `sg-vault` with the Vault labels and the `vault-tls` Secret and call
`transit/encrypt/autounseal` through the agent) and write a non-secret
marker. `make rotation-proof` (port golden_ticket's script): rotate twice
via `oc create job --from=cronjob/seal-rotator`; the old secret-id login
fails, the current one works, exactly one secret-id is valid.

### `ansible bootstrap`

Port golden_ticket's `vault_bootstrap/cluster.yml` + `tokens.yml`: wait for
`vault-0` to answer; `operator init` with **recovery keys** if
uninitialised (`.secrets/vault-init.json`, `0600`, `no_log`); wait for
`vault-1`/`vault-2` to join through `retry_join` (TLS,
`leader_ca_cert_file`); assert 3 voters, one leader, seal type `transit`;
write the platform bootstrap policies `sg-tf-platform` and
`sg-ansible-platform` and their token roles; issue
`.secrets/tokens/{tf-platform,ansible-platform}`. Assert that no Vault pod
has `VAULT_TOKEN` in its environment and no Secret in `sg-vault` holds a
token.

### Make

`make prepare`, `workloads`, `seal-init`, `seal`, `agent`, `bootstrap`
(each one phase), `make unseal`, `make status` (seal type, HA mode, leader,
voters, licence expiry, VSO CSV), `make rotation-proof`, `make vault-roll`
(controlled roll for `OnDelete`: standbys first, leader last, each back
unsealed with 3 voters before the next).

## Validation

```sh
make lab                                  # green through bootstrap
make lab                                  # every plan empty, every Ansible phase changed=0
make status                               # 3/3 unsealed, seal type transit, 1 leader, 3 voters
oc -n sg-vault exec vault-0 -- env | grep -c VAULT_TOKEN       # 0
oc -n sg-vault delete pod <active>        # standby serves; pod rejoins unsealed
oc -n sg-vault-seal delete pod -l app.kubernetes.io/name=seal-agent   # cluster keeps serving; agent re-auths
make rotation-proof                       # old 400, current 200, exactly one valid secret-id
oc -n sg-vault-seal delete pod vault-seal-0   # comes back sealed; cluster keeps serving
make unseal                               # one key; agent re-auths
# cold start: scale Vault to 0, delete vault-seal-0 → scale to 3: pods wait in Init; make unseal → all unseal
# NetworkPolicy proofs: a pod in sg-workloads cannot reach seal-agent:8200 or vault-seal:8200
```

## Out of scope

Cluster structure (prompt 03), identity (prompt 04), VSO resources
(prompt 05).

## Execution log

Appended by each run: what was done, deviations and why, validation output.
