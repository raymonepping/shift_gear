# Audit collector

`server.mjs` uses Node’s standard library to project Vault socket-audit JSON
lines into an in-memory view for the console. Terraform `workloads` owns its
ConfigMap, Deployment, Service and NetworkPolicy in `sg-app`. It runs on the
pinned UBI Node.js image without an image build; a source checksum rolls the pod.

| Endpoint | Purpose | Allowed caller |
| --- | --- | --- |
| TCP 9090 | Vault JSON-line ingest | Vault pods in sg-vault |
| HTTP 8080 /audit | Newest entries, default limit 200, capped at 500 | sg-ui |
| HTTP 8080 /archive | Latest 200 committed metadata records | sg-ui |
| HTTP 8081 /metrics | Fixed numeric series without identity labels | sg-metrics / labelled proof reader |
| HTTP 8080 /healthz | Listener readiness | Pod probes |

The buffer holds at most 1,000 entries and drops the oldest at capacity. Invalid
JSON is counted as malformed. The response includes listening, connections,
received, stored, dropped, malformed, startedAt and lastEntryAt counters.
Live counters and ring entries reset on restart. When explicitly enabled, a separate append queue commits a narrower fixed projection to a protected PVC with fsync. The archive retains at most seven days or 64 MiB, prunes generated segments only, and reports failures/drops/corruption. It excludes display names, policies and raw error values as well as payloads and credentials. Paths remain sensitive metadata. Queued records can be lost on a crash; local disk is neither tamper-evident custody nor an external backup. See [the observability contract](../docs/observability.md).

Projected fields include time, operation, namespace, request path, display name,
policies, error and names of HMAC-protected fields. The collector discards secret
values; metadata remains visible. The BFF requires a session, and the Audit page
is available to every signed-in user.

Terraform `platform` owns the socket device and the independent stdout device.
Keep stdout enabled so requests can proceed while the collector restarts.
The earlier restart proof recorded HTTP 200 throughout and reconnection on the
next audited request. `make validate` checks that an audited request increases
the received counter. The collector itself needs no Vault or Kubernetes token.

Metrics backends and archive retention default to disabled. OpenTelemetry is preferred; Prometheus is an optional alternative. The live ring requires neither. See [the opt-in configuration](../docs/observability.md#optional-configuration).
