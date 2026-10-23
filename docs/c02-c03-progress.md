# C02 and C03 delivery

Status: locally accepted on 2026-10-22; all 43 final-source live steps passed. C03 proved feasible.

Selected 2026-10-22: C02 metrics/durable audit integration and C03 if feasible. Other unfinished roadmap work is deferred, including M06 isolated restore, S03 general onboarding, S04 another substrate, C01 hosted automation and the protected release handoff. C04 and earlier delivered work remain accepted only for their recorded source revisions.

## Discovery

CRC/OpenShift are running. Monitoring namespaces and the ServiceMonitor CRD exist, but there are no running Prometheus or log-storage pods. An external destination has not been supplied. Destination preference was requested; implementation can progress on bounded metadata retention and low-cardinality metrics without publishing data externally.

C03 can use the existing Vault Agent and PostgreSQL images for one isolated dynamic-database consumer. It must have its own Kubernetes auth identity, Vault policy, database role and data scope; it must prove denial of the existing application's paths and compare rotation/recovery with VSO. This does not complete the deferred general onboarding framework or add another operator.

## Required acceptance

C02 must distinguish the live ring from retained metadata, publish bounded numeric metrics without identity/path labels, restrict access, exclude raw credential/payload/error values, prove retention across collector replacement and expiry/size pruning, expose storage failure honestly and keep the independent stdout audit device. PVC retention is not an external backup or isolated restore proof.

C03 remains conditional on working, isolated delivery plus real database checks, credential replacement/recovery, denied cross-consumer access and a documented tradeoff. Neither item is accepted by the previous C04 receipt.

## Initial C02 validation and apply

Static checks passed 18/18, offline regressions passed 52/52 (27 Python, 15 UI/HTTPS, ten collector), and UI type-check/lint passed. The first apply exposed the default CRC storage class's WaitForFirstConsumer behavior: the new PVC resources must not wait for binding before their consumer Deployments can be scheduled. A short-lived read-only binding pod was used for these two new empty claims so the in-flight apply could complete without deleting claims; source now sets `wait_until_bound=false` on both claims, with a regression assertion. New pods then reported Multus Unauthorized sandbox failures, requiring the existing targeted daemonset refresh. Neither configuration attempt is a final passing acceptance receipt.

The first C03 apply created the separate service account, audience-bound auth role, policy, database connection/schema/role and two-container workload. Both containers became ready and the actual SQL readiness probe succeeded. No existing application credential was reset. UI type-check/lint and all 52 offline regressions passed after this integration. Live isolation, expiry/restart and browser acceptance are still pending.

## Targeted verification

The first complete `make lab` passed on 2026-10-22: idempotency had no unexpected changes, all five Terraform plans were empty, the secret scan passed and evidence publication completed on the original cluster UID `bef1f3e7-a9c6-43bb-9847-a0ee756cd38c`. Run `9614f0f1-1e41-413a-8741-5148017815e3`, input digest `833b1a240862…` precedes the final proof/browser refinements and is not final-source acceptance.

The targeted C02 live proof passed 11 checks: an actual private scrape, allowed/denied network probes, refused audited login fixture, committed fixed projection, password absence in actual retained files, stable record ID/time after a real collector replacement and resumed scraping. The targeted C03 proof passed 14 checks: actual allowed and denied SQL, token/mount isolation, fresh audience/SA-bound authentication, cross-consumer denials, file replacement, retired principals and recovery after real pod replacement. These receipts bind to digest `deea7b9e8e70d516540d60e5fbc68880eb5e8090de6d6729b3827060111b4aa8`; later proof receipt hardening and Ansible variable-prefix corrections require final acceptance again.

Production Ansible lint initially rejected the new role's variable prefixes. Renaming those internal variables to the role prefix resolved it; static checks then passed 18/18. No lint exception or idempotency allowance was added. Full final-source live acceptance and visual review remain pending below.

## Owner refinement: optional OpenTelemetry preferred

The owner subsequently selected OpenTelemetry if feasible, Prometheus as the less-preferred alternative, and required both integrations to be optional with no hard dependency. Implementation now defaults to `metrics_backend="none"`, `audit_archive_enabled=false` and no observability storage. OpenTelemetry is a separately selected scraper/export adapter without a Prometheus server or persistent metrics database. Prometheus is a mutually exclusive opt-in alternative. The archive has its own switch. Existing data remains protected when runtime is disabled. Full acceptance must cover disabled behavior as well as the preferred integration; the earlier targeted Prometheus receipt does not accept this refinement.

OpenTelemetry enabled-mode verification passed all 11 live observability checks, including actual timestamped scrape export and retained marker continuity. Disabled-mode verification passed five live checks with neither backend Deployment and no collector archive mount; 18 runtime health checks and five focused browser tests passed with disabled states and the live audit link available. Existing PVCs were retained. The intermediate full convergence check correctly rejected the changed input selection; it is not counted as a green convergence run. Preferred-mode final acceptance remains pending.

The optional Prometheus mode then passed all 11 live observability checks and five focused browser tests. Disabled-mode receipt: digest `9d5e8efcbc1f96bf2c2f0064cfe1e933521b37fd81fb636e86021b3c8b57601b`; Prometheus-mode receipt: digest `67aa31a7c234fe006d15ce9d95ba482a29cf7c0afb8ca20cc3a073a71e1e2346`. These profiles are deliberately different inputs. The preferred working profile is now OpenTelemetry with archive enabled; default checkout remains neither. Final live acceptance is running on stable inputs.

## Final review corrections

The first final-source ladder stopped at C03's principal-retirement assertion after ten passing steps. The proof incorrectly allowed only thirty seconds after a credential file changed, although a replacement may overlap an existing valid lease. A read-only PostgreSQL aggregate showed two still-valid fixture principals and zero expired principals. The assertion now uses the configured 120-second maximum credential lease plus thirty seconds for revocation, matching the existing pod-restart retirement bound. It still requires actual principal deletion and retains the SQL/authentication isolation checks. The failed receipt remains in the private proof history.

Visual preview also exposed an impractical retained-record table: 9,827px desktop / 21,195px mobile pages. The view now keeps all 200 available rows in a bounded, labelled, keyboard-scrollable region with a sticky header, rather than making the entire page that tall. Source changes invalidate earlier acceptance; targeted verification and a fresh complete ladder are required again.

The corrected C03 targeted proof passed 15 actual checks. The bounded-table preflight passed 25 checks (all-screen axe at desktop/phone and reduced motion, Agent cards, 195/320/390px containment, observability API/failure/disabled/keyboard checks and both screenshot runs). Visual inspection then identified overly narrow mobile metric columns; local table scrolling now preserves readable names and timestamps. A final targeted layout preview and complete acceptance run follow.

The refined table layout passed ten focused containment/API/interaction/screenshot checks, followed by five mobile-browser checks including actual horizontal keyboard scrolling. Reviewed phone observability height is now 2,986px (all 200 records remain available in the local scroll region); Agent cards and source/runbook links remain intact. Final acceptance now runs against digest `f087a49e28cd987bdc9ca2d6c1f47882274ba6f611eb565bf353768edce7f498`. Its first eleven steps passed, including 18 static checks, 53 offline regressions, UI checks, all 11 selected observability checks and all 15 actual consumer checks. Full reconciliation, browser/scenario ladder and final source/identity verification remain pending.


## Final local acceptance — 2026-10-22

C02 and C03 are complete within the selected lab scope. The final live ladder passed **43/43 ordered steps** on unchanged sources, including **18/18 static checks**, **53/53 offline regressions** (27 Python, 16 UI/HTTPS, ten collector), UI type-check/lint, certificate/expiry/component/access/upgrade proofs, **11/11 selected observability checks**, **15/15 actual consumer checks**, repeated full reconciliations, **148/148 standard browser tests**, the dedicated UI failover journey, both screenshot runs, all nine scenarios with subsequent health checks, final convergence/drift and dependency inventory. The inventory found zero mutable active image references. Browser TLS verification remained enabled.

| Identity | Accepted value |
| --- | --- |
| Proof | `c9f4e52c-aaa0-4716-be75-c743444472a0` |
| Input digest | `f087a49e28cd987bdc9ca2d6c1f47882274ba6f611eb565bf353768edce7f498` |
| Checkout revision | `4286faf00998e10893c8fc36cbafd440f17b049f` (dirty local workspace) |
| Cluster UID | `bef1f3e7-a9c6-43bb-9847-a0ee756cd38c` — unchanged from the original target |
| Final run | `c6e3ab63-c9e8-4a00-a035-973415e5586a` |
| Completion | 2026-10-22 14:05:19 Europe/Amsterdam (12:05:19 UTC) |
| Selected optional profile | OpenTelemetry + archive enabled; protected storage retained |

The final run and convergence record agree with the proof's digest, cluster and run identity; provisioning and publication both succeeded. The exact 43 commands and their order match the shared acceptance contract. Private receipts are `.build/proof-manifest.json`, `.build/observability-proof.json`, `.build/consumer-proof.json` and `.build/dependency-inventory.json`; sanitized status does not include tokens, passwords or raw audit bodies.

Post-cold-start read-only checks confirmed OpenTelemetry's actual `up=1` export, available archive storage with 7,259 retained rows and the original 09:56:09 UTC segment, and a successful isolated consumer SQL read. CRC and OpenShift are running on the same cluster UID. The cold-start scenario stopped and restarted CRC; it did not reset the cluster or restore persistent data. Podman was not stopped or changed.

All 30 final screenshots were generated. The observability and Agent desktop/phone images were visually reviewed: readable locally scrolling metric columns, bounded retained table, accessible source/runbook links and the third Agent card. The phone observability page is 2,986px high instead of 21,195px, while all latest 200 records remain available. Contextual ownership links lead to the observability and consumer runbooks.

Repository defaults remain `metrics_backend="none"`, `audit_archive_enabled=false`, `observability_storage_enabled=false`: a fresh core lab requires neither integration nor observability PVCs. This working lab explicitly opts in through the ignored, non-secret `terraform/workloads/observability.auto.tfvars`, whose contents are included in the input digest. OpenTelemetry is preferred; Prometheus remains an independently selectable alternative. Disabled and Prometheus modes have their separate passing live/browser checks recorded above. Disable runtime while retaining `observability_storage_enabled=true` after use to preserve protected data. See [configuration and retention](observability.md#optional-configuration).

Limits remain explicit: OpenTelemetry is a private current-metrics adapter, with no configured external OTLP destination or historical metrics store. The metadata archive is a bounded local PVC projection, not full native audit custody, tamper evidence, host-loss recovery or M06 isolated restore. The Agent consumer proves scoped secret delivery and pod/lease recovery, not persistent-database restoration. Host Node 25 remains outside the UI package's declared engine range; deployed/build runtimes retain their reviewed Node 24 image and the recorded checks passed without widening engine support.

Other unfinished work remains deferred: M06 isolated restore, S03 general onboarding, S04 another substrate, C01 hosted automation and protected release handoff. The local receipt records `dirty=true`; it cannot authorize a protected release. No commit, push, tag, external publication or protected live CI execution occurred. Article drafts were not changed in this C02/C03 task.
