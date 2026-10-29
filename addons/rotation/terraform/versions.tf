# addons/rotation/terraform — the removable KV rotation add-on (ADR D17).
#
# Not in scripts/phases.txt. Applied and destroyed only by `make rotation-up`
# / `make rotation-down` (scripts/tf-run.sh rotation …). Destroying this root
# never touches a managed secret: values and history live in the core `kv`
# mount and are written by the controller, not by Terraform.
terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  backend "local" {
    path = "../../../.secrets/terraform/rotation/terraform.tfstate"
  }

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.11"
    }
  }
}

# KUBE_CONFIG_PATH, VAULT_ADDR, VAULT_TOKEN (tf-platform) and VAULT_CACERT are
# set by scripts/tf-run.sh; VAULT_NAMESPACE is unset (lesson 16) and every
# Vault resource names its namespace explicitly.
provider "kubernetes" {}
provider "vault" {}
