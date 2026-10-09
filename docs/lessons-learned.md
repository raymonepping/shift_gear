# Lessons learned

Lessons from the full predecessor series (`multi_pass`, `red_pass`, `golden_ticket`,
`red_doors`) carried forward, plus what Shift Gear found during its own build.

---

## From the predecessor series

**L01 — Contracts win.**
A stable output contract (`cluster` output from `terraform/infra/`) lets tools compose without
coupling. `multi_pass` proved this for VMs. Shift Gear extends it to a cluster API.

**L02 — Evidence wins.**
Nothing is green until something checked it. A badge without a drawer is a lie. Every gate
in `make lab` writes a JSON file before asserting — so a failed run still produces an
inspectable result.

**L03 — A platform needs both answers.**
Lifecycle questions (create a mount, declare a namespace) belong to Terraform. Order-and-moment
questions (init, unseal, seed a credential) belong to Ansible. Mixing them leads to plans
that fail because the infrastructure they need does not yet exist, or Ansible tasks that
create resources Terraform then tries to adopt.

**L04 — The boundary is a policy, not a convention.**
`golden_ticket` introduced the four bootstrap tokens, each with a distinct Vault policy.
The boundary is not a team agreement — it is enforced by `sys/capabilities-self` on every
`make boundary` run. A cultural rule can be overridden by a deadline; a Vault policy cannot.

**L05 — `VAULT_NAMESPACE` must be unset, not inherited.**
If `VAULT_NAMESPACE=shift-gear` is set in the environment and a Terraform root targets the
seal Vault (which has no `shift-gear` namespace), every `vault_*` resource fails with
`namespace not found`. `tf-run.sh` explicitly unsets `VAULT_NAMESPACE`.

**L06 — Single-use secret-ids require a fresh generation on every deploy.**
AppRole secret-ids with a `secret_id_num_uses=1` are consumed on first use. Re-running
`make agent` generates a fresh one. The old accessor is expired. This is correct behaviour
— document it, do not fight it.

**L07 — Raft peer traffic requires port 8201.**
The Vault pod TLS cert must cover both `vault.apps-crc.testing` (port 8200) and the internal
service name for raft (port 8201). A cert without the internal SAN causes raft join to fail
with `tls: certificate is valid for X but not Y`.

**L08 — `abspath` is required for kubeconfig in Terraform.**
`path.root` in Terraform is relative to the module directory, not the project root.
`abspath("${path.root}/../../${var.kubeconfig_path}")` resolves correctly regardless of where
`terraform` is invoked from.

**L09 — Keycloak groups mapper must be `multivalued: true`.**
Without `multivalued: true`, only the first group membership is included in the JWT
`groups` claim. `bound_claims` checks on `groups` fail for users in more than one group.

**L10 — TLS `notBefore = now - 1h` absorbs clock drift.**
After a Mac sleep, CRC VM clock can drift by up to 90 seconds. Certs issued at `T=0` with
`notBefore=T` are rejected by nodes that still think it is `T-70s`. A 1-hour back-date is
sufficient for any reasonable NTP drift and does not materially affect security.

**L11 — `serverAuth + clientAuth` EKU on Vault pod certs.**
The seal agent's mTLS listener requires client auth. Vault pods present their own cert as a
client cert to the seal agent. `serverAuth` only causes the mTLS handshake to fail.

**L12 — VSO CSV gate: never apply CRDs before `Succeeded`.**
The OLM installs the VSO CSV asynchronously. Applying a `VaultConnection` while the CSV is in
`Installing` results in `no kind "VaultConnection" is registered`. Poll until `Succeeded`.

**L13 — `$(VAR)` expansion in Makefile vs. shell.**
`$(VAR)` in a Makefile recipe is expanded by Make, not the shell. Use `$${VAR}` for
shell variables inside a recipe, or delegate to a script.

---

## From the Shift Gear build

**L14 — OpenLDAP `k8s_exec` is the only viable path from a Mac controller.**
The Mac cannot reach `openldap.sg-identity.svc:1389` — it is not exposed. Using
`kubernetes.core.k8s_exec` to run `ldapadd` inside the pod is the correct pattern for
in-cluster operations that have no Route.

**L15 — Keycloak `firstName` maps from `givenName`, not `cn`.**
The default Keycloak LDAP mapper for `firstName` uses `cn`. For standard LDAP entries,
`cn` is the full name. Mapping from `givenName` gives the first name only. This affects
Vault `bound_claims` on `given_name` in JWT auth.

**L16 — ConfigMap evidence path for the UI API pod.**
A stateless API pod on CRC cannot mount a host path or a `ReadWriteMany` PVC. Ansible syncs
`.build/*.json` into a ConfigMap; the pod mounts it as a volume. `make ux` is idempotent:
it only updates changed keys.

**L17 — Clock drift cascade: Mac sleep → CRC VM → projected SA tokens.**
After a Mac sleep, the CRC VM's clock can jump forward by more than the 5-minute leeway on
Kubernetes projected SA tokens. Vault returns `403` on Kubernetes auth. `chrony` hardening
(`makestep 1.0 -1`, `maxpoll 6`) in the CRC VM resolves this. `scripts/crc-post-start.sh`
applies chrony config after every `crc start`.

**L18 — Stale builder token after a long stop.**
The BuildConfig for OpenLDAP uses the builder SA token. After a long `crc stop`, the SA token
expires. `make ux` triggers a new build, which generates a fresh token. If the build fails
with `401 Unauthorized`, delete the old builder pod and re-run `make ux`.

**L19 — DB lease lapsed during Mac sleep.**
PostgreSQL dynamic credentials have a 1-hour TTL. After a Mac sleep longer than 1 hour, the
VSO `VaultDynamicSecret` lease has lapsed. VSO requests a new credential automatically on
the next sync cycle. If the `db-creds` Secret is stale, `oc -n sg-workloads delete secret db-creds`
forces an immediate refresh.

**L20 — AppRole lockout: `secret_id_num_uses=1` on the rotator.**
The rotator CronJob generates a secret-id with `num_uses=1`. If the job runs twice in quick
succession (e.g., after a failed run and a retry), the second job cannot authenticate because
the secret-id was consumed. The fix: the rotator always generates a new secret-id at the
start, not the end, of its run.

**L21 — Substrate isolation grep must exempt `crc-*.sh` delegation lines.**
`scripts/down.sh` calls `scripts/crc-down.sh` and `scripts/crc-up.sh` by name. The grep for
substrate isolation (`crc`) would match these delegation lines. The check script exempts
lines matching `crc-[a-z-]+\.sh` with `grep -vE 'crc-[a-z-]+\.sh'`.
