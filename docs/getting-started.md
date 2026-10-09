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

The CRC bootstrap script reads this path. It is in `.gitignore` and `.secretignore`.

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

**Expected duration:** 15–20 minutes on first run (image pull + cluster bootstrap).
Subsequent `make crc-up` calls take 3–5 minutes.

---

## 4. Full stack: `make lab`

```sh
make lab
```

`lab.sh` runs all 13 phases from `scripts/phases.txt`, then three gates
(`idempotency`, `secret-scan`, `boundary`). Progress is printed as each phase starts.
On failure the exact resume command is printed:

```
FAILED: ansible configure
Resume:   make configure
Rerun:    make lab
```

**Expected duration (first run):** 35–45 minutes.

Per-phase indicative timings:

| Phase | Tool | Typical |
|---|---|---|
| infra | tf | ~30 s |
| foundation | tf | ~2 min |
| prepare | ansible | ~3 min (waits for VSO CSV) |
| workloads | tf | ~8 min (Helm releases pull images) |
| seal-init | ansible | ~1 min |
| seal | tf | ~30 s |
| agent | ansible | ~30 s |
| bootstrap | ansible | ~2 min |
| platform | tf | ~1 min |
| identity | ansible | ~4 min |
| configure | ansible | ~2 min |
| ux | ansible | ~3 min (BuildConfig image build) |
| validate | ansible | ~1 min |
| gates | — | ~3 min |

These are indicative — image pulls and CRC VM scheduling vary. Check
`docs/operations.md` for recorded timings from the reference run.

---

## 5. Verify the stack

```sh
make verify
```

Expected output ends with `verify-stack passed` and no `✗` rows.

---

## 6. First sign-in

Get `ada`'s password:

```sh
make identity-show-user PERSON=ada
```

Open `https://vault.apps-crc.testing` in your browser. Trust the project CA
(`.secrets/tls/pub/ca.pem`) or add it to your keychain.

Sign in with method **OIDC** and username `ada`. You will be redirected to Keycloak.
On return, Vault shows `ada`'s token policies: `sg-engineer`, `sg-staff`.

Open `https://sg-ui.apps-crc.testing` for the Shift Gear console.

---

## 7. `make identity-show-user`

Print any user's password from Vault KV:

```sh
make identity-show-user PERSON=ben
make identity-show-user PERSON=cleo
make identity-show-user PERSON=dirk
make identity-show-user PERSON=finn
```

---

## 8. Second `make lab` (idempotency proof)

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
