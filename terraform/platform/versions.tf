terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  backend "local" {
    path = "../../.secrets/terraform/platform/terraform.tfstate"
  }

  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.11"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.6"
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
  cluster = data.terraform_remote_state.infra.outputs.cluster
}

# VAULT_ADDR  = https://vault.<apps_domain>  (set by tf-run.sh from infra output)
# VAULT_TOKEN = content of .secrets/tokens/tf-platform  (set by tf-run.sh)
# VAULT_CACERT = .secrets/tls/pub/ca.pem               (set by tf-run.sh)
# VAULT_NAMESPACE is unset by tf-run.sh (lesson 16: prevents double-prefix)
provider "vault" {}

provider "http" {}
