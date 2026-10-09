# Troubleshooting

Real problems encountered during the Shift Gear build. Symptom → cause → fix.

---

## Clock jump after Mac sleep

**Symptom:** `make validate` or `make identity-verify` fails with Vault returning `403` on
Kubernetes auth. The Vault log shows `token has expired`.

**Cause:** After a Mac sleep, the CRC VM clock jumps forward (the hypervisor clock pauses during
sleep; the guest clock does not advance). Kubernetes projected SA tokens have a 5-minute
leeway. If the guest thinks it is `T+0` but Vault's clock (synced via the Route from the
Mac) thinks it is `T+8m`, the token looks expired.

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
Secret has a stale secret-id (from before the CRC VM was stopped and restarted). If the
secret-id was single-use and was consumed before the stop, the agent cannot re-authenticate.

**Fix:**
```sh
make agent   # generates a new secret-id; restarts the seal-agent pod
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

**Cause:** The rotator ran twice in quick succession (e.g., a failed CronJob retried). The
`num_uses=1` secret-id was consumed on the first run; the second run used a new secret-id that
was also consumed. The seal agent pod now has a secret-id that was already used.

**Fix:**
```sh
make agent    # generates a fresh secret-id; deploys it to the Secret; restarts the pod
```

If the AppRole role itself is blocked (all accessors revoked):
```sh
VAULT_TOKEN=$(cat .secrets/tokens/ansible-seal) \
vault write -f auth/approle/role/sg-seal-autounseal/secret-id \
  -address=https://vault-seal.apps-crc.testing \
  -ca-cert=.secrets/tls/pub/ca.pem
# Note the secret_id, then run make agent
```

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

**Cause:** The builder SA token in `sg-app` expired after a long `make crc-stop`.

**Fix:**
```sh
oc -n sg-app delete pod -l openshift.io/build.name   # delete stale builder pods
oc -n sg-app serviceaccounts new-token builder        # issue a fresh token (OCP 4.11+)
make ux
```

---

## DB lease lapsed during sleep

**Symptom:** `workload-b` pods show `Error` or the `db-creds` Secret has a past `lastSyncTime`.
`make vso-status` shows `syncError: lease has expired`.

**Cause:** The PostgreSQL dynamic credential lease (TTL 1h) expired while the Mac was asleep.
VSO's sync cycle did not run because the CRC VM was stopped.

**Fix:**
```sh
oc -n sg-workloads delete secret db-creds   # VSO re-creates immediately
make vso-status                             # confirm lastSyncTime is recent
```

---

## TLS certificate verify failed

**Symptom:** `curl: (60) SSL certificate problem: unable to get local issuer certificate` when
accessing `https://vault.apps-crc.testing`.

**Cause:** The project CA (`ca.pem`) is not trusted by the system or by `curl`'s CA bundle.

**Fix:**
```sh
# For curl commands:
curl --cacert .secrets/tls/pub/ca.pem https://vault.apps-crc.testing/v1/sys/health

# For browser: trust the CA
# macOS:
security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db \
  .secrets/tls/pub/ca.pem
```

All `scripts/` that call Vault use `--cacert "${CA_FILE}"` where `CA_FILE` points to
`.secrets/tls/pub/ca.pem`. If this file is missing, run `make prepare` to regenerate.

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
