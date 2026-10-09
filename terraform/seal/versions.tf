terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  backend "local" {
    path = "../../.secrets/terraform/seal/terraform.tfstate"
  }

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.11"
    }
  }
}

data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = "../../.secrets/terraform/infra/terraform.tfstate"
  }
}

locals {
  # pod_cidr from the substrate contract: all Vault agent pods live within
  # this network. Pod IPs are not stable, so the CIDR is the correct bound —
  # the per-pod restriction is enforced by the NetworkPolicy (D8).
  pod_cidr = data.terraform_remote_state.infra.outputs.cluster.pod_cidr
}

# Address and token come from the environment only (scripts/tf-run.sh).
# VAULT_TOKEN = content of .secrets/tokens/tf-seal
# VAULT_CACERT = .secrets/tls/pub/ca.pem
# The seal Vault Route address is used here; the internal address would work
# but the Route is how Ansible also reaches it, keeping a single CA path.
provider "vault" {
  # Address overridable via VAULT_ADDR; tf-run.sh sets it from the workloads output.
}
