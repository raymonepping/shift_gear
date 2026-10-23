# Tool, field and check ownership

| Area | Desired-state owner | Runtime writer / exception | Proof |
| --- | --- | --- | --- |
| Namespaces, RBAC, deployments, Helm, Routes, policies and mounts | Terraform | Controllers populate public metadata; no general spec exemption | Empty plans and mutation tests |
| Vault initialization, credentials, auth configuration and seed values | Ansible | Scoped bootstrap exception for init-root custody | Repeat-run stats, live auth and state audit |
| Reviewer identity | Terraform ServiceAccount/RBAC; Vault projected token | Kubernetes rotates the pod token; no credential resource in Terraform | Fresh Kubernetes login and no JWT in current state |
| Seal Agent template marker | Ansible | `shift-gear/credentials-rotated` only | Credential repair plus empty workload plan |
| Workload restart marker | VSO | `vso.secrets.hashicorp.com/restartedAt` only | Rotation and empty workload plan |
| Evidence ConfigMap | Ansible UX | One exact named task in `scripts/idempotency-tasks.json` | Callback records actual changed tasks; all others fail the exception |
| KV rotation from console | Signed-in operator via Vault policy | CAS-protected application write; not a desired-structure owner | Direct HTTP denies, receipt/retry and conflict tests |

`policies/boundary-matrix.json` is the reviewed allowed/denied operation registry used by the live boundary check. A changed policy requires review of this matrix and an added positive/negative probe where appropriate. The check asks Vault for actual capabilities; it does not infer them from a UI role.

## Dry-run coverage

| Area | Check-mode coverage | Separate proof |
| --- | --- | --- |
| Kubernetes object modules | Module-supported desired-state comparison; API required | Terraform drift and live validation |
| Vault auth/config URI tasks | Explicit reads; writes subject to module/check-mode behavior | Real reconciliation repeat and auth probes |
| LDAP federation/password/group commands | Incomplete: command tasks may skip check mode | Scenario 08 fresh login before/after membership mutation and restoration |
| In-cluster image builds | Builds deliberately skipped in check mode | Source/image digest decision and real repeat-run task events |
| Evidence publication | Timestamped ConfigMap is the one allowed changed task | Served observation identity and generation check |
| Init, unseal and credential repair | Real runtime operation, not established by dry-run alone | Bootstrap repeat, cold-start, rotation and expiry proofs |

“Unsupported” means no proof from that check, not a passing task. `make drift` covers Terraform and the supported Ansible checks; it does not replace the real scenarios. The check-mode table is part of release scope and must evolve with the tasks.

The target lock survives a temporary CLI outage only when the ancestor lock is still verified and the complete ordered kubeconfig fingerprint is unchanged. A changed config requires fresh target resolution. A configured target that cannot be resolved fails closed instead of acquiring an unrelated bootstrap lock. This preserves exclusion through nested cold-start commands; it is not an authority grant from an environment variable alone.


## Selected Should extensions

The UI observer's projected identity can only GET four named VSO/deployment resources in `sg-workloads` and `Deployment/seal-agent` in `sg-vault-seal`; it has no Secret or mutation permission. Dedicated component-proof fixtures and snapshot-reader roles are Terraform structure, while scoped Ansible maintenance tokens request short-lived proof/download identities. Snapshot download is a privileged maintenance capability, not routine console observation.

Ansible produces and reconciles console/LDAP image digest inputs; Terraform consumes the same private digest-only catalog on workloads plan/apply/drift. The named image field has no lifecycle exception. Other image fields remain ordinary Terraform desired state. OLM is Manual and a separate UID/CSV-bound helper performs explicit approval.


OpenShift owns the observer ServiceAccount's registry pull-secret references and its exact `openshift.io/internal-registry-pull-secret-ref` annotation. Those fields are narrowly exempted; RBAC, the automount default and other metadata remain Terraform desired state. This is not Secret data in state and does not grant the observer permission to read a Secret.

## Read-only explorer

The versioned `policies/ownership-map.json` registry carries the declared owner/writer/exception/check rows published at `/explorer`. Update it with this document when ownership changes. The explorer includes the unchanged `policies/boundary-matrix.json` expectations and source hashes; it does not execute capability checks or expose credential values. See the [explorer contract](policy-ownership-explorer.md).

C02 adds Terraform-owned collector and optional OpenTelemetry/Prometheus workloads, protected PVCs and private service access; the collector and Prometheus own runtime retention. C03 splits Terraform pod identity/memory-volume ownership from Ansible Vault/database configuration. Vault Agent owns file replacement and Vault owns lease revocation. See [observability](observability.md) and [Agent database delivery](agent-database-consumer.md).
