# Credential custody and renewal

The normal tool boundary is separate from emergency bootstrap authority. Root/init files stay in `.secrets/` with private directory/file permissions; they are never evidence artifacts. The four scoped periodic tokens are issued/renewed by seal-init/bootstrap. `make credential-status` reports their metadata only and audits current state; `make doctor` separately reports API identity, Vault seal state and certificate expiry. Neither command starts/stops a VM.

## Projected reviewer migration

Terraform manages the Vault `system:auth-delegator` binding to ServiceAccount `vault`. Vault Kubernetes auth uses that pod's rotating projected reviewer JWT. The Terraform `removed` block forgets the old Secret without prematurely deleting it. After `make foundation bootstrap configure`, `scripts/retire-reviewer.sh` proves a new Kubernetes-auth login and revokes that short-lived proof token before retiring the old Secret. `make state-audit` must pass on every current state.

Terraform's prior state backups and `.secrets/archive/` can contain the now-retired JWT. They remain confidential, mode 0600, outside delivery artifacts. The default public/current-state scan inventories their permissions without claiming their contents are value-free. Do not publish them. Custody review decides encrypted retention or explicitly authorized disposal; neither silently deleting backups nor rewriting history is a security proof.

## Certificate renewal

`make prepare` renews expiring leaves under the existing trusted CA. Each new key/certificate is staged privately and its chain and validity checked before installation and Kubernetes Secret update. Set `SG_TLS_RENEW_LEAVES=1 make prepare` for an intentional leaf-renewal drill, then perform the controlled Vault roll and restart the proxy/Agent consumers that load certificates at startup. Verify with `make verify`, `make boundary` and browser tests using TLS verification. Do not use this flag to replace the CA.

An existing invalid/missing/near-expiry CA fails preparation rather than silently creating a new trust anchor. For a root trust change:

1. Inventory all clients: Vault listeners and clients, seal Agent mTLS, Keycloak proxy, BFF, host/browser trust and automation.
2. Establish protected custody of old/new keys and a target-bound rollback plan. Generate the new CA separately; do not overwrite `.secrets/tls/ca.key` in place.
3. Stage an old+new trust bundle across all consumers and verify old chains still work. Restart/reload startup-only consumers while the old leaves remain in use.
4. Issue new leaves under the new root, validate both certificate uses/SANs, then roll standbys before leader. Verify Agent proxy and identity paths independently.
5. Prove all clients use the new chain before removing old trust. Keep old recovery material under its custody/retention policy.

Root CA replacement is a separate trust migration and is not claimed proven by a same-root leaf renewal. No TLS bypass is permitted during either operation.

## Expired Agent credentials

The agent secret-id expires after 24 hours; the rotator secret-id is a distinct, non-expiring credential. `make agent` reads the current ID, reuses a valid one, and replaces an invalid/expired ID using the scoped Ansible seal token. The credential-rotation pod-template annotation is Ansible-owned. `make rotation-proof` verifies retirement/current lookup/count after recovery. Routine observation never uses an init root token; recovery of expired bootstrap tokens is an explicit bootstrap task.

## Final state and recovery

`make down`, `make up` and reset have distinct postconditions. Failed scaling/deletion cannot report successful completion. Reset requires both its project confirmation and the actual `CONFIRM_CLUSTER_ID` from `make doctor`, in addition to a dry-run. A run must leave the host runtime in the state selected by the operator; successful testing is not authorization to switch back to another VM.

The isolated data-restoration proof M06 is deferred at the operator's request. No snapshot/restore claim follows from the earlier reconstruction proof. The future recovery run must include both Raft stores, original seal dependencies, protected key custody, isolated DB/identity dependencies and a post-bootstrap canary. See the [PRD recovery journey](PRD.md#j07--restore-data-not-merely-rebuild-structure).

## Reproducible credential drills

`make credential-expiry-proof` issues a two-second SecretID through the scoped Ansible seal token, verifies its metadata expiry before replacing the Agent's Kubernetes credential, runs the normal `make agent` repair and explicit accessor retirement, verifies a fresh replacement login and rejects predecessor reuse. The installed Vault build can retain and accept expired SecretIDs until cleanup; the repair checks `expiration_time` and explicitly revokes the replaced accessor rather than treating lookup HTTP 200 as proof of validity. Credential bodies stay in memory. Failure restores the original credential and restarts the Agent; the private command log explains the failed step.

`make certificate-proof` protects the previous TLS directory under `.secrets/tls-renewal/<timestamp>/`, forces leaf renewal, asserts the root fingerprint is unchanged and the leaf changed, restarts startup-only consumers, rolls main Vault standbys before its leader and verifies the certificates actually served by both Vault Routes. The backup contains private keys: keep its parent private and apply the same custody/retention decision as other recovery material. No private TLS backup is a public proof artifact. On interruption, inspect readiness first; restore the protected previous files, run normal `make prepare` to republish Secrets and roll affected consumers under the unchanged CA. Do not replace the root to repair a leaf failure.

Keycloak also needs the OpenShift ingress CA to verify outbound BFF logout callbacks. Preparation publishes that public certificate alongside the project CA; Terraform mounts it in Keycloak's `KC_TRUSTSTORE_PATHS`. This uses [Keycloak's supported truststore configuration](https://www.keycloak.org/server/keycloak-truststore), preserving certificate and hostname verification. The BFF separately verifies Keycloak's signing-key endpoint using the project CA.

`make doctor` distinguishes the VM process from CRC control/status, API identity and individual Vault seal states. A setup/status error is not evidence that the VM is down. `scripts/crc-health.sh --require-control` guards shutdown before workloads are scaled. A clock jump after host sleep can make JWTs and snapshots appear invalid; `scripts/crc-post-start.sh` measures and corrects node clock skew without switching runtimes. Investigate persistent skew and resource contention rather than weakening timestamp checks.

CRC startup detaches the hypervisor process group from short-lived controller sessions. Cold startup reauthenticates and probes the seal Agent before main Vault starts, waits for actual unsealed members plus HA metadata, and resets an unavailable demo Agent's initialization backoff after Vault is ready. Kubernetes bootstrap readiness deliberately accepts sealed Vault pods; it is never sufficient evidence of unsealed Raft health.

The clock helper also verifies that `chronyd` is active and reachable and that the final node clock agrees with the host within five seconds. A standalone `maxpoll` line previously stopped the daemon; the helper removes it. `maxpoll` belongs on a source directive, as specified in [Chrony's configuration reference](https://chrony-project.org/doc/latest/chrony.conf.html). An active service alone is not proof of upstream synchronization; inspect `chronyc tracking` when skew recurs.

CRC control commands run with a private temporary kubeconfig and remove it on return, including failure. `crc stop` otherwise clears the inherited project connection entries, changing target identity during a nested cold start. The project kubeconfig is refreshed explicitly after startup; the cold-start scenario verifies that shutdown leaves its bytes unchanged. This control isolation is separate from the target lock's verified-inheritance and fail-closed checks.

Bootstrap reconciliation also checks a token's reported TTL and renewability. Lookup HTTP 200 can expose retained metadata for a token whose period has elapsed; it is not enough to establish renewability. The bootstrap phase issues a replacement through its existing root-authorized role, persists it privately, then retires the previous accessor before attempting renewal. Routine observation never falls back to that root authority.
