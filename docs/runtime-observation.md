# Runtime observation contract

The console retains host-published snapshots for declared structure, phases and historical convergence. `/api/v1/runtime` adds independent read-only observations after authentication; it never relabels the mounted ConfigMap as a live source.

| Source | Read and authority | What it establishes | What it does not establish |
| --- | --- | --- | --- |
| Vault | TLS-verified GET of active service `sys/health`; no Vault token | Active-service response shape, initialized/sealed/standby flags | All-member unseal, Raft quorum or application authorization |
| Seal chain | TLS-verified, unauthenticated `sys/health` for Seal Vault and each fixed `vault-0/1/2` internal DNS name; named GET of `Deployment/seal-agent` in `sg-vault-seal` | Initialized/unsealed members, exactly one reported active member, current-generation Agent availability | Transit decrypt, token TTL, Raft quorum, recovery or future auto-unseal |
| Identity | TLS-verified realm discovery; no user or bootstrap credential | Discovery document answered | Successful user authentication or intended policy assignment |
| VSO | GET only named `VaultStaticSecret/app-config` and `VaultDynamicSecret/db-creds` in `sg-workloads` | Latest status metadata exposed by each CR | Delivery of a particular rotation ID/version |
| Consumers | GET only `Deployment/workload-a` and `Deployment/workload-b` in `sg-workloads` | Ready/updated replica counts and observed generation | Application consumption of a particular secret |

Terraform owns `sg-ui-observer`, namespaced Roles and their bindings. The BFF receives its rotating projected service-account token. It can GET the four named resources in `sg-workloads` and only `Deployment/seal-agent` in `sg-vault-seal`. It cannot list/watch resources, read any Secret, execute pods, mutate objects or use cluster-admin. There is no static Kubernetes credential in Nuxt configuration. Project CA and service-account CA verification remain enabled. Upstream URLs and resource names are fixed by server code, never accepted from browser input.

Every probe has a three-second absolute HTTP deadline and a 64 KiB response limit, follows no redirects and returns only explicitly projected metadata. Probes run independently; an identity or Kubernetes outage cannot make Vault look unavailable or healthy. Responses distinguish available, unavailable, denied and invalid, with actual observation/check times. Upstream error bodies never enter the UI.

Requests share an in-flight collection and a ten-second server cache. The console checks in the foreground every 15 seconds with one shared polling loop; hidden tabs pause polling and are checked immediately when visible again. Requests have a five-second browser deadline with no automatic retry. A displayed result older than 30 seconds is stale. The topbar and Fleet/Cluster seal diagrams use these live observations, independently of the historical snapshot. Green requires all five chain sources fresh, Seal Vault initialized/unsealed, the Agent at its desired updated/available replica count and generation, all three members initialized/unsealed, and exactly one member reporting active. A failed refresh withdraws the previous green label immediately; the clock expires retained observations even if requests stop. Valid Vault sealed/uninitialized health codes are negative observations, not generic HTTP outages. These are bounded status observations, not a continuous telemetry or availability guarantee.

Terraform permits only `sg-app` pods labelled `app.kubernetes.io/name=sg-ui` to reach Seal Vault on port 8200, alongside its existing permitted callers. The UI receives no Seal Vault token or Agent mTLS credential, and no network access to the Agent proxy is added. The Agent check observes Deployment readiness only. The native Kubernetes endpoints remain restricted by named GET-only RBAC. Neither a Prometheus server nor OpenTelemetry is needed.

The source disclosure includes owner/resource, timestamps and contextual investigation steps. Snapshot evidence keeps its own 120-second freshness threshold and source/run/cluster identity. Operator rotation remains accepted-unverified until a separate correlated delivery proof exists; a changed VSO timestamp or ready deployment cannot upgrade its receipt to delivered.

Transport faults use fixed reason labels: timeout, response too large, TLS trust, connection or missing local configuration. HTTP refusal and malformed payloads remain distinct from successful observations. Raw upstream errors, response bodies and file paths are never passed to the browser. Shared page feedback reports loading, unavailable responses and sanitized HTTP status with an accessible retry; it labels retained data as previous observations.

The [23 October seal-chain follow-up](seal-chain-observation.md) records implementation scope, actual permission/network checks and browser/convergence validation.
