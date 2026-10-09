# Scenario 08 — Drift detection

**Purpose**: Prove each tool detects its own layer of drift — Terraform for infrastructure and Vault structure, Ansible for configuration.

## 3-line presenter script

```bash
# Vault mount drift (Terraform detects)
vault namespace login -namespace=shift-gear && vault secrets disable -namespace=shift-gear transit
make platform  # tf plan rc=2 → detects missing transit mount → apply restores it

# LDAP group drift (Ansible identity-verify detects)
# Add ben to engineers in the LDAP admin UI, then:
make identity-verify  # fails for ben → make identity restores membership
```

## Four sub-scenarios

| # | Drift introduced | Tool that detects | Fix command |
|---|---|---|---|
| 1 | Disable the `transit` Vault mount | `terraform/platform plan` (exit 2) | `make platform` |
| 2 | Edit workload-a image directly | `terraform/workloads plan` (or `ignore_changes` proves intent) | `make workloads` |
| 3 | Change a Keycloak client in the admin UI | `ansible identity --check` (changed > 0) | `make identity` |
| 4 | Add ben to the `engineers` LDAP group | `make identity-verify` fails for ben | `make identity` |

## How to run

```bash
bash scenarios/08_drift_detection/run.sh
```

## Why this works

Terraform's `plan -detailed-exitcode` reports exit 2 when it would make changes — it acts as a structural diff tool.  Ansible `--check` mode re-reads the actual state and reports what it *would* change — it acts as a configuration diff tool.  `make identity-verify` is a pure read-only proof: it logs in with real credentials and compares actual identity_policies against expected ones, so a manual LDAP change is immediately visible.
