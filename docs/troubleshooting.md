# Troubleshooting

Real problems encountered during the Shift Gear build. Symptom → cause → fix.

---

## Clock jump after Mac sleep

**Symptom:** `make validate` or `make identity-verify` fails with Vault returning `403` on
Kubernetes auth. The Vault log shows `token has expired`.

**Cause:** Mac sleep can leave the CRC guest clock behind. Expired projected
service-account tokens then fail Kubernetes authentication. Vault runs in the
same VM; an OpenShift Route does not synchronize its clock.

**Fix:**
```sh
crc stop && crc start     # forces guest NTP resync
# OR: if using scripts/crc-post-start.sh:
make crc-up               # post-start script runs chrony makestep
```

`scripts/crc-post-start.sh` applies `makestep 1.0 -1` and `maxpoll 6` to the CRC VM's
chrony configuration, which allows immediate step-correction on restart.

---

## `$(VAR)` expansion in Makefile

**Symptom:** A Makefile recipe using `$(PERSON)` in `make identity-show-user PERSON=ada`
passes an empty string to the script.

**Cause:** Make expands `$(PERSON)` to empty if `PERSON` is not defined as a Make variable.
When passed on the command line as `PERSON=ada`, Make sets it as a Make variable — this is
correct. The issue arises when the recipe uses `$(PERSON)` inside a shell construct that Make
interprets before passing to the shell.

**Fix:** The Makefile target passes `$(PERSON)` directly as a positional argument to the script:
```makefile
identity-show-user:
    @./scripts/identity-show-user.sh $(PERSON)
```
This works because Make expands `$(PERSON)` and the result is passed to the shell.

---

## Seal agent unreachable after `make up`

**Symptom:** `make up` succeeds but `make verify` shows `✗ Seal agent: not available`.

**Cause:** The seal agent pod is running but cannot authenticate because the `seal-agent-approle`
Secret has a stale secret-id (from before the CRC VM was stopped and restarted). The agent role permits repeated logins; a consumed single-use ID is not the current configuration.

**Fix:**
```sh
make agent   # replaces an absent or expired secret-id; otherwise reuses the valid one
make verify
```

---

## Expired agent secret-id after a long stop

**Symptom:** `make up` shows the seal agent pod in `CrashLoopBackOff`. Vault log: `invalid secret_id`.

**Cause:** AppRole secret-ids have a `secret_id_ttl` (default: 24h). If the CRC VM was stopped
for longer than the TTL, the secret-id expired.

**Fix:** Same as above — `make agent` generates a fresh secret-id:
```sh
make agent
oc -n sg-vault-seal rollout status deploy/seal-agent
```

---

## `VAULT_NAMESPACE` double-prefix

**Symptom:** Terraform apply fails with `mount path not found` or `policy not found` on a path
that clearly exists.

**Cause:** `VAULT_NAMESPACE=shift-gear` is set in the shell environment. The Vault Terraform
provider uses this as a prefix on every path. If the resource already has
`namespace = "shift-gear"` in its HCL block, the effective path becomes
`shift-gear/shift-gear/sys/mounts/kv` — which does not exist.

**Fix:** `scripts/tf-run.sh` unsets `VAULT_NAMESPACE` before every Terraform call. If running
Terraform manually, unset the variable first:
```sh
unset VAULT_NAMESPACE
cd terraform/platform && terraform apply
```

---

## AppRole lockout

**Symptom:** `make rotation-proof` fails. The seal Vault returns `429 Too Many Requests` or
`400 Bad Request` on all subsequent secret-id logins.

**Diagnosis:** The agent ID permits repeated logins and expires after 24 hours.
Check the role’s lifetime and CIDR bindings, the rotator Job status and agent
authentication errors. Repeated failed logins can trigger lockout; the proof
must distinguish this from an absent ID.

```sh
make agent    # reconciles AppRole material and restarts the agent when needed
make rotation-proof
```

Do not copy a secret-id into the terminal. The agent phase handles credentials
under `no_log` and persists them only in the intended Kubernetes Secret.

---

## VSO CSV not ready

**Symptom:** `make workloads` fails with `no kind "VaultConnection" is registered`.

**Cause:** The VSO operator Subscription was just created by `make foundation`. The OLM is still
downloading and installing the operator. The CSV has not reached `Succeeded`.

**Fix:** `make prepare` polls for CSV `Succeeded` before allowing the phase to complete.
If `make workloads` was run manually before `make prepare`:
```sh
oc -n openshift-operators get csv -w   # wait for Succeeded
make workloads                         # re-apply
```

---

## Stale builder token

**Symptom:** `make ux` fails with `401 Unauthorized` on the BuildConfig. The `oc start-build`
command outputs `error: unauthorized`.

**Diagnosis:** Distinguish an expired controller kubeconfig from a build pod's
registry authentication failure. Do not delete every build pod or manufacture
a service-account token without identifying which request returned 401.

```sh
make crc-up               # refresh kubeconfig and post-start checks
oc -n sg-app get builds
# Inspect the failed build's status and logs, then retry:
make ux
```

---

## DB lease lapsed during sleep

**Symptom:** `workload-b` pods show `Error` or the `db-creds` Secret has a past `lastSyncTime`.
`make vso-status` shows `syncError: lease has expired`.

**Cause:** The PostgreSQL dynamic credential lease (default TTL 5m, maximum 10m) expired while the Mac was asleep.
VSO's sync cycle did not run because the CRC VM was stopped.

**Fix:**
```sh
oc -n sg-workloads delete secret db-creds   # VSO re-creates immediately
make vso-status                             # confirm lastSyncTime is recent
```

---

## TLS certificate verify failed

**Symptom:** `curl: (60) SSL certificate problem: unable to get local issuer certificate` when
accessing `https://vault.apps-crc.testing` or `https://shiftgear.apps-crc.testing`.

**Cause:** The project CA (`.secrets/tls/pub/ca.pem`) is not trusted by macOS.

**Fix — browser:**
```sh
make trust
```

Adds the CA to the System keychain. Quit and reopen Chrome for it to take effect.

**Fix — curl (without adding to keychain):**
```sh
curl --cacert .secrets/tls/pub/ca.pem https://vault.apps-crc.testing/v1/sys/health
```

All `scripts/` that call Vault use `--cacert "${CA_FILE}"` pointing to `.secrets/tls/pub/ca.pem`.
If this file is missing, run `make prepare` to regenerate it.

---

## `make check` substrate grep false positive

**Symptom:** `make check` fails the substrate grep with a match in `scripts/down.sh` on a
line calling `scripts/crc-down.sh`.

**Cause:** `down.sh` delegates to the substrate scripts by name. The word `crc` appears in
the script name.

**Fix:** The grep in `scripts/check.sh` exempts lines matching `crc-[a-z-]+\.sh`:
```sh
grep -vE 'crc-[a-z-]+\.sh'
```
If a new delegation line is added, ensure it matches this pattern.

## Audit collector unreachable

The Audit page reports unreachable rather than falling back to a snapshot.
Check `oc -n sg-app get deployment sg-audit`, its readiness and its logs, then
inspect `sg-audit-ingress`: TCP 9090 admits Vault pods; HTTP 8080 admits sg-ui.
`make workloads` reconciles the collector; `make platform` reconciles both
Vault devices. Keep the stdout device enabled. The earlier restart proof found
that Vault kept serving and reconnected on the next audited request. Collector
entries and counters start again after a restart.

## Cluster or Operator page does not change after a scenario

These pages read the host-published evidence snapshot. A browser reload reads
the same mounted file. Run `make ux` and wait for its evidence-timestamp check,
then reload. The Audit page has a separate live collector request.

## Identity reports changed=1 for sg-cli on every run

An empty `valid_post_logout_redirect_uris` list creates an empty Keycloak
attribute that Keycloak removes. The client task now omits this parameter for
sg-cli while retaining the Vault client’s configured logout redirects. Two
consecutive `make identity` runs must report changed=0.

### Seal chain: not currently verified

The topbar and Fleet/Cluster seal diagrams use independent live observations, not the published snapshot. Open Runtime sources to see each fixed source and its sanitized failure reason. Checks run every 15 seconds in a visible tab; results expire after 30 seconds and failed requests withdraw the previous healthy status. An old published snapshot remains old even when live seal health is green.

For a missing Seal Vault response, inspect project CA trust, service reachability and the Terraform-owned `vault-seal-ingress` rule for labelled UI pods. For denied Agent status, inspect `sg-ui-seal-observer` Role/binding in `sg-vault-seal`, then run `make observer-boundary`. An available Agent Deployment is readiness evidence only. Use `make verify` for full operational checks; do not reset Vault or loosen TLS to repair an observation failure.
