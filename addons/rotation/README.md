# addons/rotation — KV v2 value rotation

> Policy-driven rotation and distribution of application-owned static secrets
> using HashiCorp Vault KV v2 and Vault Agent.

A removable add-on that rotates Vault KV v2 values on a schedule, after use, on
an event, or on request. Every secret declares `owner: application`; anything
Vault or an external provider owns is refused, with the right alternative
named ([when KV rotation makes sense](../../docs/rotation.md#when-kv-rotation-makes-sense-who-owns-the-credential)). The full description is in [docs/rotation.md](../../docs/rotation.md),
and the decision record is D17 in [docs/decisions.md](../../docs/decisions.md).

```text
addons/rotation/
├── rotation.yaml          declarative types, generators, schedules, policies, secrets
├── rotation.mk            make rotation-* (included by the core Makefile)
├── controller/rotation/   the controller — Python 3.12 standard library only
├── controller/tests/      unit tests (unittest; fake KV v2 with CAS)
├── cli/rotation_cli.py    status · history · rotate · read · report (host)
├── terraform/             the add-on root: namespace, pod, NetworkPolicies, Vault policies
├── policies/              Vault ACL policy templates (rendered from rotation.yaml)
├── ansible/               preflight · configure (auth role, groups) · verify · down
├── scripts/               rotation.sh (lifecycle), validate.sh (offline gate)
├── tests/live/            make rotation-test (s01–s12 + leak check) and its overlay
├── consumer/              the Secure Door: verifier + client + board (make rotation-consumer-*)
└── ASSESSMENT.md          the 01_01 probe results this design rests on
```

## What the controller needs from a host

The controller (`controller/rotation/`) knows nothing about OpenShift. A host
must provide:

| Need | Shift Gear (OpenShift) | A Podman host (e.g. Red Pass) would use |
| --- | --- | --- |
| A Vault namespace with a KV v2 mount | `shift-gear`, mount `kv` | the same |
| A machine identity with `sg-rotation-controller` | Kubernetes auth, Vault Agent sidecar with `api_proxy` on loopback | AppRole (with a bounded lockout) and a Vault Agent container with the same `api_proxy` |
| Its configuration as JSON | Terraform ConfigMap from `rotation.yaml` | a rendered file mounted read-only |
| The audit stream, for the usage strategy (optional) | the `sg-audit` collector's `GET /audit` | any endpoint with the same shape; without one, usage reports "not available" |
| Vault event notifications (optional) | a `vault-events` sidecar writing NDJSON | the same command in a container; without it, the checkpoint poll still catches every change |
| A scheduler for the process | a Deployment (one replica, `Recreate`) | a systemd unit or a Quadlet |

Settings are `ROTATION_*` environment variables (see the module docstring in
`controller/rotation/controller.py`), never `VAULT_*`.

## Working on it

```sh
make rotation-validate             # offline: unit tests, config, terraform test, ansible-lint, shellcheck
make rotation-up && make rotation-test
make rotation-test S=04            # one scenario
```

The add-on lives outside the core convergence digest, so editing it never
makes `make verify` report a stale lab.
