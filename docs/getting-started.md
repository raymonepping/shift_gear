# Getting started

This document walks through a first run of Shift Gear from a clean Mac. No manual steps after
`make crc-up && make lab`. Follow each section in order.

---

## 1. Pull secret

Get your pull secret from [console.redhat.com/openshift/create/local](https://console.redhat.com/openshift/create/local).
Save it to:

```sh
mkdir -p .secrets/crc
cp ~/Downloads/pull-secret.txt .secrets/crc/pull-secret.txt
```

The CRC bootstrap script reads this path. It is covered by `.gitignore`.

---

## 2. `.env`

Create `.env` in the project root:

```sh
VAULT_LICENSE=02MMVV...   # your Vault Enterprise licence key
```

Only `VAULT_LICENSE` is read. `RHSM_*` keys may be present (they are not consumed — CRC
manages its own Red Hat entitlement internally).

---

## 3. Start OpenShift Local

```sh
make crc-up
```

This runs `scripts/crc-up.sh` which:

1. Sets the CRC preset to `openshift`.
2. Sets resources: 8 vCPU, 24 576 MB RAM, 80 GB disk.
3. Runs `crc setup` then `crc start --pull-secret-file .secrets/crc/pull-secret.txt`.
4. Runs `scripts/crc-post-start.sh` (waits for kubeconfig, copies it to `.secrets/kube/config`).

Startup time depends on image downloads and the local VM. Fresh-build timings
remain pending the rebuild proof in `docs/operations.md`.

---

## 4. Full stack: `make lab`

```sh
make lab
```

`lab.sh` runs all 13 phases from `scripts/phases.txt`, then three gates
(`idempotency`, Terraform `drift`, `secret-scan`). Progress is printed as each phase starts.
On failure the exact resume command is printed:

```
FAILED: ansible configure
Resume:   make configure
Rerun:    make lab
```

The first-run duration has not yet been measured on a fresh VM without
intervention. See [Operations](operations.md) for the measured converged re-run
and the pending rebuild table. `make lab` prints phase and gate durations;
`make lab-times` prints the last saved table without running anything.

---

## 5. Verify the stack

```sh
make verify
```

Expected output ends with `verify-stack passed` and no `✗` rows.

---

## 6. Trust the CA (once)

```sh
make trust
```

Adds `.secrets/tls/pub/ca.pem` to the macOS System keychain. Chrome, Safari, and `curl` all
accept the cert after this — no more browser warnings. Quit and reopen Chrome for it to take effect.

Remove it later with `make untrust`.

---

## 7. First sign-in

Get `ada`'s password:

```sh
make identity-show-user PERSON=ada
```

Open `https://shiftgear.apps-crc.testing` for the Shift Gear console. Sign in with username
`ada` — Keycloak handles the redirect. On return, `ada`'s identity policies include `sg-engineer` (alongside the token's default policy). The `staff` directory group deliberately carries no policy.

For the Vault UI directly: `https://vault.apps-crc.testing` → set **Namespace** to `shift-gear` (the auth methods exist only there; the root namespace answers "permission denied") → method **OIDC** (Keycloak) or **LDAP** with a persona, e.g. `ada`, whose password `./scripts/identity-show-user.sh ada` prints.

---

## 8. `make identity-show-user`

Print any user's password from Vault KV:

```sh
make identity-show-user PERSON=ben
make identity-show-user PERSON=cleo
make identity-show-user PERSON=dirk
make identity-show-user PERSON=finn
```

---

## 9. Second `make lab` (idempotency proof)

```sh
make lab
```

On the second run:

- Every `terraform plan` exits with 0 changes.
- Every Ansible phase reports `changed=0` (except the documented evidence-sync tasks).
- The three gates re-run and all pass.

---

## Common pre-flight failures

| Symptom | Cause | Fix |
|---|---|---|
| `crc: command not found` | CRC not installed or not in PATH | Install CRC; add to PATH |
| `.secrets/crc/pull-secret.txt: No such file` | Pull secret not placed | See step 1 |
| `VAULT_LICENSE is required` | `.env` missing or incomplete | See step 2 |
| `VSO CSV not yet Succeeded` | VSO operator still installing | `make prepare` retries automatically (up to 20×30 s) |
| `kubeconfig not found` | `make crc-up` not yet run or CRC stopped | `make crc-up` |
| `TLS: certificate verify failed` | Project CA not trusted | Trust `.secrets/tls/pub/ca.pem` |
