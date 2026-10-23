# C02 metrics and retained metadata

Metrics and archive retention are independent opt-ins. The default core lab has neither a telemetry backend nor observability PVCs. OpenTelemetry is the preferred adapter; a pinned Prometheus LTS instance is the alternative. Both run privately in `sg-app` only when selected. The collector exposes fixed numeric Prometheus series on port 8081. Its existing HTTP read port 8080 exposes the live ring and a separate bounded metadata archive. `/observability` reads enabled sources through authenticated fixed BFF requests; disabled sources cause no upstream request and are labelled disabled, not failed; `/audit` links to that view and retains its existing volatile semantics. Neither browser API accepts PromQL, URLs, credentials or filesystem paths.

Terraform owns workloads, private Services, NetworkPolicies, PVCs and retention limits. OpenTelemetry, Prometheus and the audit collector have no service-account token or API roles. Only the metrics-reader pod selector may scrape port 8081; the existing UI selector may read port 8080. Only the UI selector may read the selected adapter's output. No public Prometheus Route or admin/lifecycle endpoint is enabled. Internal HTTP follows the existing namespace-restricted audit transport; this is not end-to-end TLS. External destinations require a separately configured, TLS-verified connection and credential custody.

## Optional configuration

| Input | Default | Meaning |
| --- | --- | --- |
| `metrics_backend` | `"none"` | `"opentelemetry"` preferred; `"prometheus"` alternative; `"none"` deploys neither |
| `audit_archive_enabled` | `false` | Enable the narrower retained projection independently of metrics |
| `observability_storage_enabled` | `false` | Provision protected PVCs for archive/Prometheus; neither OTel nor the live ring requires them |

Copy `terraform/workloads/observability.tfvars.example` to the ignored `observability.auto.tfvars` to opt in locally, then reconcile with `make lab`. The non-secret selection file participates in the automation input digest. `make` needs no telemetry environment variable for a default checkout. Archive or Prometheus requires `observability_storage_enabled=true`; OTel alone does not.

To disable runtime **after** data has been created, set `metrics_backend="none"` and `audit_archive_enabled=false`, keeping `observability_storage_enabled=true`. The deployments disappear and the collector stops mounting its archive; retained PVCs remain protected. Setting storage false after use intentionally fails the destruction guard instead of deleting data. Storage retirement is separate reviewed maintenance. Optional backend Deployments do not wait for rollout in the core workloads phase; their selected proof reports unavailable collection honestly. Core UI readiness, authentication, secret delivery and the live ring do not require those services.

The current working lab explicitly opts into OpenTelemetry plus archive retention for acceptance. This local opt-in does not change the repository defaults. The previously allocated Prometheus PVC is retained even while Prometheus is disabled.

## Retention contract

The live ring retains up to 1,000 projected entries and resets with its counters on process restart. It does not become a durable source because a separate archive exists.

The archive appends a narrower fixed projection: stable record ID, original Vault time, collector retention timestamp, request type/operation/namespace/path and a boolean error flag. Raw payloads, tokens, credentials, actor names, policies and raw error strings are excluded. Paths remain potentially sensitive operational metadata. Every signed-in person can read this projection under the existing audit readership contract. It is not anonymized or a full native Vault audit log.

Writes use a bounded 1 MiB/1,024-record queue, segments up to 256 KiB and fsync before committed counters advance. A PVC preserves committed rows across collector replacement. Pending rows can be lost on a crash; queue saturation and write failure cause visible gaps instead of blocking Vault. Failed/malformed storage and partial records are not invented as observations. Restarts reset process counters; the retained-entry/byte gauges describe the current disk archive.

Archive retention is at most seven days or 64 MiB, whichever limit is reached first, with pruning on writes and a 30-second maintenance interval. Whole oldest segments are removed, so a byte bound can shorten retention. Only generated archive segment names are pruned; unrelated files are not removed. The UI shows the latest 200 retained records, not a complete historical search/export interface. Reload never changes a row's original timestamps.

OpenTelemetry scrapes the collector every ten seconds and exposes bounded current samples through its private Prometheus-format exporter. This uses a protocol exporter, **not a Prometheus server dependency**. Original scrape timestamps are included and preserved by the BFF; unrelated series and all labels are excluded from browser output. Its memory limiter and batching bound processing, and unrefreshed samples expire after sixty seconds. It is a collection adapter, not historical metrics storage. There is no configured external OTLP destination and no claim of external delivery or trace collection. An external destination would require its own reviewed endpoint/trust/credential configuration.

In the alternative mode, Prometheus keeps up to seven days / 128 MB of time-series blocks on a 1 GiB PVC. Its WAL/head and compaction overhead are additional to the block-retention size; the PVC is not an exact 128 MB disk cap. The query uses one minute of raw samples to retain actual scrape timestamps instead of relabelling the instant-query evaluation time as a fresh scrape. Stale samples and a failed query are distinct.

When explicitly provisioned, both PVCs have Terraform `prevent_destroy` in the workloads root. This does not protect against namespace/cluster deletion, privileged storage changes or loss of the CRC host. Local PVCs are neither an external backup nor M06 isolated recovery. The independent stdout Vault audit device remains enabled. The asynchronous socket collector does not provide an exactly-once, tamper-evident or compliance audit guarantee.

## Proof and operations

Use the selected delivery record for actual results: [C02/C03 progress](c02-c03-progress.md). Tests cover projection/redaction, recovery after process replacement, partial-write handling, unavailable storage and age/size pruning. Live acceptance must also verify numeric scraping, allowed/denied network access, BFF authentication, actual retained marker continuity across collector replacement and convergence afterward. No failing storage check may be represented as healthy retention.

If storage is unavailable, inspect the named PVC and collector permissions/capacity through the operator's host tools. Keep the stdout device enabled while repairing. Do not delete the PVC or reset the cluster to repair collector availability. Do not place raw logs, private snapshots or credentials into evidence or public proof bundles.

References: [OpenTelemetry pipelines](https://opentelemetry.io/docs/collector/configuration/), [exported sample timestamps](https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/exporter/prometheusexporter/README.md), [Collector 0.163.1 release](https://github.com/open-telemetry/opentelemetry-collector-releases/releases/tag/v0.163.1), [Prometheus text exposition](https://prometheus.io/docs/instrumenting/exposition_formats/), [Prometheus storage and retention](https://prometheus.io/docs/prometheus/latest/storage/), [official releases](https://prometheus.io/download/). The selected image resolves the 3.13.5 LTS multi-architecture manifest to `sha256:aafa9d694e6a883c02db516d9f6e5b84e14195f49a2a6456a4cca815edda72b9`; actual deployed identity must be checked by the inventory.

The optional OTel 0.163.1 image is pinned to multi-architecture digest `sha256:1175b03003053962012f5a231f5567f66a3e8fdb960c7835c0e48f7aa1555806`; the reviewed arm64 manifest is `sha256:068c276ab8e011c294c707129435fea004dd230d9f20797520e4cad68a28540e`.
