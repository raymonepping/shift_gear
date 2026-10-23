# Dependencies and controlled upgrades

## Selected baseline

Provider selection is recorded in the five root `.terraform.lock.hcl` files, now deliverable source files. Routine `scripts/tf-run.sh` initialization uses `-lockfile=readonly` and never `-upgrade`. A dependency change is a separate reviewed change: update constraints/lockfiles deliberately, inspect signatures/checksums, include the required platforms with `terraform providers lock`, and run the static/mock plus live gates. Package signatures identify publishers; they do not replace review. See [Terraform lockfiles](https://developer.hashicorp.com/terraform/language/files/dependency-lock) and [platform checksum acquisition](https://developer.hashicorp.com/terraform/cli/commands/providers/lock).

| Component | Selected configuration / verification |
| --- | --- |
| Terraform | `>=1.11`, roots with narrower bounds retain them; exact installed version and provider selections recorded by `make dependency-inventory` |
| Kubernetes provider | Existing locked `2.38.0`; tested with the existing OpenShift 4.22.14 arm64 lab |
| Helm provider / Vault chart | Locked `2.17.0`; chart `0.30.0` for both releases |
| Vault provider / HTTP provider | Existing locked `5.12.0` / `3.6.2`; exact roots recorded in the inventory |
| Vault Enterprise | Existing `2.1.0-ent` image digest retained; no persistent-data binary upgrade or downgrade in this increment |
| Identity | Existing Keycloak `26.2.5` and HAProxy digest pins retained; PostgreSQL 16 pinned to the observed arm64 image |
| Audit collector | Reviewed UBI Node 22 digest as rollback baseline; selected UBI Node 24 arm64 digest for the collector runtime upgrade rehearsal |
| Build bases | Node 24 slim and Alpine 3.22 pinned to registry-provided multi-architecture manifest-list digests; npm uses `package-lock.json` |
| Workload / CLI images | UBI Micro pinned to its manifest-list digest; cluster CLI resolved as an immutable substrate output beside the unchanged connection contract |
| Built console / LDAP | Ansible records resolved ImageStream digest inputs privately and pins the named container image; Terraform consumes the same explicit variables without an image-field ignore exception |
| VSO | Stable channel with **Manual** install-plan approval; actual installed CSV recorded in the dependency inventory |

This is a tested profile, not a claim that every OS/architecture or combination in a version range was exercised. The provider `zh` checksums cover signed release packages; add/verify platform-specific `h1` entries before expanding the supported runner matrix. Runtime inventory distinguishes configured image references from the resolved image IDs; both are needed to interpret multi-architecture images.

## Image ownership

Terraform owns deployments and image inputs. Ansible builds console/LDAP artifacts, resolves their immutable references and writes `.secrets/deployment-images.tfvars.json` (digest references only, private by default). It reconciles only the named image field with a resource-version precondition. The Terraform wrapper validates this catalog's exact keys, repositories and digest shape and supplies it to every workloads plan/apply/drift. Routine drift still detects an unauthorized image change. A missing image input permits a tag only during first-build bootstrap; after the normal image phases, deployed templates must contain digest references.

Preserve the image catalog with the existing lab's private operational inputs. If it is lost, use the normal image phases to reconstruct it from reviewed ImageStream state before accepting convergence. Do not add broad lifecycle `ignore_changes` to conceal drift. Build-base digests do not freeze live Alpine package repository contents; archive build provenance/artifact identities if a byte-identical rebuild is required.

## Operator approval

OLM cannot silently advance this subscription. Review the referenced InstallPlan, its exact CSV, compatibility/release notes and backup prerequisites first. Then explicitly select it:

```sh
VSO_APPROVE_CSV=<exact-reviewed-csv-name> make vso-approve
```

The helper requires Manual mode, the subscription's current plan reference, matching plan UID and owner, and exactly the selected CSV. Its JSON patch tests the UID and CSV again at write time. An unknown or additional CSV is refused. Initial installation also needs this approval after foundation creates the subscription; run it before `make prepare` waits for operator readiness. [OpenShift's OLM approval model](https://docs.redhat.com/en/documentation/openshift_container_platform/4.15/html/operators/administrator-tasks) describes this mechanism; verify behavior against the installed cluster and CSV before approving an update.

## Pre-upgrade custody

`make upgrade-snapshot` downloads and structurally inspects both Raft stores into a new mode-0700 directory beneath `.secrets/pre-upgrade/`, with mode-0600 files, hashes and the actual cluster UID. Two-minute scoped identities can download snapshots and revoke themselves; they cannot restore or force-restore. Terraform owns their policy/role structure and Ansible's scoped maintenance credentials can request them. No init/root credential is read by the download tool. This export privilege is sensitive even though it cannot modify Vault: restrict maintenance token custody and review its use.

A partial failure keeps confidential files private, emits no passing receipt and blocks the upgrade. The sanitized `.build/upgrade-snapshot.json` contains only status, time, cluster identity and store count. It does not contain snapshot content, private paths or credentials. Local copies do not meet an external backup-custody or isolated-recovery objective. Select encryption, external storage, retention and a separate recovery target before accepting M06. No automatic disposal of historical snapshots or TLS/state backups is performed.

## Supported rehearsal and its limits

`make upgrade-proof` first requires fresh private snapshots. It reconciles the previous immutable Node 22 collector, upgrades to the selected Node 24 digest, proves audit traffic reaches the replacement, rolls back the configuration to Node 22 and proves audit delivery again, then reapplies Node 24 and rechecks delivery. Instance IDs must change. On failure after the baseline is established it restores the previous collector and verifies it; a failed rollback remains a failure requiring operator investigation.

Since C02 the collector has a bounded metadata archive on a protected PVC. The Node runtime rehearsal uses the same source and archive format throughout; it does not downgrade or restore that format. Its live buffer/counters reset during replacement, and S06 reports that restart to an active visitor. The independent stdout audit device remains configured. This rehearsal establishes configuration rollback and resumed audit delivery for this component. It does not establish restoration of incompatible Vault, database, LDAP or Keycloak data. Never use an older image as an assumed rollback for a changed data format. Isolated data restoration remains explicitly deferred under M06.

After any upgrade, run the complete source-bound proof ladder and retain the dependency inventory, sanitized proof and configuration change. Raw logs and snapshots remain private. Review a different component's compatibility and recovery procedure separately before changing it.

The observed selected collector runtime is Node `v24.21.0`; the installed VSO CSV is `vault-secrets-operator.v1.6.1` under Manual approval. The targeted upgrade/config-recovery rehearsal passed on 2026-10-16. Final source-bound acceptance is recorded separately in `docs/should-progress.md`.

Inventory enforces immutable references on active pods and every current Deployment/StatefulSet/CronJob template. Finished Job pods retain their historical configured references and available runtime image IDs, with a separate historical mutable-reference count; they are not rewritten or erased to make the report green. Missing runtime IDs stay null/empty rather than being invented from the configured reference.

The observed local controller is Terraform `1.14.2` with Node `v25.2.1`. That Node version is outside the UI package's declared engine ranges; record it as the observed local test interpreter, not a supported installation target. The checked-in CI configuration selects Node 24, and both the console build/runtime and selected collector use Node 24 images. A local passing test run does not expand the package's declared support range or prove the protected CI profile has executed.
