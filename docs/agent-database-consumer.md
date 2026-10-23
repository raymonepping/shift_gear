# Isolated Agent database consumer (C03)

This fixture compares file delivery by Vault Agent with the existing Vault Secrets Operator (VSO) delivery path. It uses the existing pinned Vault and PostgreSQL images and database server, with a separate `sg_agent.canary` table. It does not introduce another operator or a general onboarding framework.

| Concern | Existing VSO workload | Isolated Agent consumer |
| --- | --- | --- |
| Authentication | `vso-workloads` service account and Vault role | `sg-agent-db` service account and role, JWT audience `vault` |
| Vault access | Existing `sg-vso` policy / `demo-reader` role | Only `database/creds/agent-reader` |
| Delivery | Operator writes a Kubernetes Secret consumed by the workload | Agent renders a mode-600 pgpass file into a memory-backed volume; application mounts it read-only |
| Token boundary | Operator holds its Vault authentication | Only the Agent mounts the projected JWT; no token sink or default service-account mount |
| Application data | Existing `public.demo` fixture | Only `sg_agent.canary`; existing application table is denied |
| Replacement | VSO reconciles its lease and Secret; application must consume replacement | Agent manages leased template credentials; application reopens the file on each connection |
| Pod recovery | Kubernetes Secret can outlive the application pod | Memory file disappears; a new Agent must authenticate and acquire a fresh credential |
| Cost / dependency | Shared operator and persisted Secret object | Per-pod Agent CPU/memory and Vault availability during initial acquisition |

Terraform owns the service account, workload, projected JWT, memory volumes, ConfigMap and network access. Ansible owns the narrow Vault policy/auth role, isolated database connection and role. Runtime credentials never enter Terraform state, an application environment variable, a Kubernetes Secret, a proof receipt or browser evidence. The bootstrap password exists in Ansible memory and then Vault's storage; sensitive tasks use `no_log`. PostgreSQL's native administrator remains the bootstrap authority. The isolated connection has CREATEROLE and grant options for its own table; this is a privileged database service account, not an unprivileged application principal.

The dedicated connection is initialized only when absent. Reconciliation refuses an unexpected existing connection target rather than resetting its password. The original rotated `vault_admin` connection is not reused. Dynamic credentials have a 60-second default and 120-second maximum lease for this bounded fixture. These short settings exercise replacement; they are not a universal production recommendation. Revocation removes the role's table/schema/database grants and drops the principal. PostgreSQL database-level PUBLIC defaults still apply; this fixture proves table isolation, not a separate database security perimeter.

The consumer establishes a new PostgreSQL connection every five seconds and marks readiness only after the canary query succeeds. It suppresses credential-bearing client errors. Its published Agent card reports deployment readiness from the snapshot; it does not fabricate lease lifetime or last rotation. A transient replacement boundary can produce an unsuccessful query before the next iteration recovers.

## Verification and recovery

After `make lab`, run `make consumer-proof`. The proof uses actual SQL reads, an expected permission denial, fresh short-lived authentication identities, cross-consumer Vault denials, token/mount inspection, credential replacement, database-principal retirement and a real consumer pod replacement. It revokes its temporary proof tokens and writes only check names, result, time and source digest to `.build/consumer-proof.json`. It does not print passwords, JWTs or generated database usernames.

For an unavailable consumer, inspect deployment readiness and sanitized Agent errors on the host, verify the audience-bound role and dedicated connection, then reconcile with the owning phases. Do not reset the original database root credential or delete storage to repair a fixture. File replacement can precede old-lease expiry; overlap does not by itself indicate an expired credential leak. The proof requires actual principal removal within the 120-second maximum credential lifetime plus thirty seconds of revocation grace. Pod replacement loses its memory file; the old lease can remain until Vault revokes it within its bounded lifetime. A Vault or PostgreSQL outage requires service recovery; this fixture does not restore their data. M06 remains deferred.

Template behavior and the optional token sink are described in [Vault Agent templates](https://developer.hashicorp.com/vault/docs/agent-and-proxy/agent/template); the explicit JWT file is described in [Kubernetes auto-auth](https://developer.hashicorp.com/vault/docs/agent-and-proxy/autoauth/methods/kubernetes).

Acceptance is recorded in [the C02/C03 delivery record](c02-c03-progress.md). Implementation alone does not establish a passing live proof.
