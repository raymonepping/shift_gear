# Substrate contract

---

## The thesis

The Vault platform — its policies, Ansible roles, VSO resources, and Terraform modules above
`infra` — does not know what it runs on. Only one file knows: `terraform/infra/`. Everything else
consumes a six-field `cluster` output.

This means: to move Shift Gear from CRC to ROSA, vSphere OCP, or bare-metal, you replace
`terraform/infra/` with a new implementation, run `terraform apply`, and re-emit the same
contract. Nothing above `infra` changes. No Ansible role changes. No policy changes. No VSO
resource changes.

---

## The `cluster` output

From [`terraform/infra/outputs.tf`](../terraform/infra/outputs.tf):

```hcl
output "cluster" {
  description = "OpenShift cluster connection contract. Stable across substrate implementations."
  value = {
    api_url         = var.api_url
    apps_domain     = local.apps_domain
    pod_cidr        = local.pod_cidr
    kubeconfig_path = var.kubeconfig_path
    ingress_ca_path = local.ingress_ca_path
    registry_host   = "image-registry.openshift-image-registry.svc:5000"
  }
}
```

| Field | What any substrate must provide | Discovered from cluster? |
|---|---|---|
| `api_url` | The OpenShift API server URL | No — passed as `var.api_url` (default: `https://api.crc.testing:6443`) |
| `apps_domain` | The wildcard Route domain | **Yes** — read from `ingresses.config.openshift.io/cluster` `.spec.domain` |
| `pod_cidr` | The pod network CIDR | **Yes** — read from `networks.config.openshift.io/cluster` `.status.clusterNetwork[0].cidr` |
| `kubeconfig_path` | Path to a valid kubeconfig | No — passed as `var.kubeconfig_path` (default: `.secrets/kube/config`) |
| `ingress_ca_path` | Path to the ingress TLS CA | **Yes** — extracted from `ingress-operator` secret in `openshift-ingress-operator` |
| `registry_host` | In-cluster image registry hostname | No — constant for all OCP clusters |

Three of the six fields are discovered from the running cluster. The other three are variables
with defaults suitable for CRC.

---

## The isolation rule

No file outside `terraform/infra/` and `scripts/crc-*.sh` may reference:

- `crc`
- `vfkit`
- `api.crc.testing`
- `apps-crc.testing`

`make check` enforces this with a grep:

```sh
grep -rn --include='*.tf' --include='*.yml' --include='*.yaml' \
     --include='*.sh' --include='*.hcl' --include='*.json' \
     -E 'crc|vfkit|api\.crc\.testing|apps-crc\.testing' \
     terraform/foundation terraform/workloads terraform/seal terraform/platform \
     ansible policies deploy \
  | grep -v '#.*crc' \
  | grep -vE 'crc-[a-z-]+\.sh'
```

Expected result: zero matches. A single match is a build failure.

---

## Substrate table

| Substrate | What must change | What does not change |
|---|---|---|
| CRC (current) | Nothing — this is the reference implementation | Everything |
| Any OCP cluster (ROSA, vSphere, bare-metal) | `terraform/infra/` variables (`api_url`, `kubeconfig_path`) | All other Terraform roots, all Ansible roles, all policies, all VSO resources |
| Different wildcard domain | Nothing — `apps_domain` is discovered from the cluster | All Routes use `${var.apps_domain}` from the contract |
| Different pod CIDR | Nothing — `pod_cidr` is discovered from the cluster | The `sg-ui` token role CIDR and NetworkPolicies use it |

---

## Worked example: existing OCP cluster

Suppose you have a vSphere OCP cluster at `api.ocp.example.com:6443` with kubeconfig at
`~/.kube/ocp-config`.

**Files that change:**

```sh
# terraform/infra/terraform.tfvars (create or update)
api_url         = "https://api.ocp.example.com:6443"
kubeconfig_path = ".secrets/kube/ocp-config"
```

Copy your kubeconfig to `.secrets/kube/ocp-config`.

**Files that do not change:**

- `terraform/foundation/`, `terraform/workloads/`, `terraform/seal/`, `terraform/platform/`
- All `ansible/` roles and playbooks
- All `policies/`
- All `deploy/`
- All `scripts/` except `scripts/crc-*.sh` (those are substrate scripts, unused for non-CRC)

Run:

```sh
make infra   # re-emits the contract from the new cluster
make lab     # all subsequent phases consume the contract
```

**The substrate isolation grep still passes** — because no new file was modified that
mentions `crc`.

---

## What is proven and what is not

The contract has **one implementation** today: CRC. The grep proves that nothing above
`terraform/infra/` mentions CRC. It does not prove that the full `make lab` run succeeds on
ROSA or vSphere. That proof requires a run on a second cluster.

What is proven:

- Every Route hostname is `*.${apps_domain}` — discovered from the cluster.
- Every CIDR-bound policy and NetworkPolicy uses `${pod_cidr}` — discovered from the cluster.
- The `kubernetes` Terraform provider uses `kubeconfig_path` from the contract.
- Ansible reads Vault addresses from `.build/terraform/*.json` (not from hardcoded hostnames).
- No Ansible role SSHes to a node — all communication is through the Vault API or
  `kubernetes.core.k8s_exec`.

What would need verification on a second cluster:

- That the OLM (Operator Lifecycle Manager) is present and the VSO Subscription installs.
- That the in-cluster image registry is reachable at `image-registry.openshift-image-registry.svc:5000`.
- That the ingress CA extraction from `openshift-ingress-operator` works on the target version.
