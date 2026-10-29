# addons/rotation/consumer/terraform — the Secure Door consumer (prompt 01_09).
#
# Its own namespace and state, independent of the rotation controller's root:
# `make rotation-down` never touches it and `make rotation-consumer-down` never
# touches the controller. Run through scripts/tf-run.sh rotation-consumer …
terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  backend "local" {
    path = "../../../../.secrets/terraform/rotation-consumer/terraform.tfstate"
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

data "terraform_remote_state" "infra" {
  backend = "local"
  config = {
    path = "../../../../.secrets/terraform/infra/terraform.tfstate"
  }
}

# KUBE_CONFIG_PATH, VAULT_ADDR, VAULT_TOKEN (tf-platform), VAULT_CACERT come
# from scripts/tf-run.sh; VAULT_NAMESPACE is unset (lesson 16).
provider "kubernetes" {}
provider "vault" {}
