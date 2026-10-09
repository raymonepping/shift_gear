terraform {
  required_version = ">= 1.11.0, < 2.0.0"

  backend "local" {
    path = "../../.secrets/terraform/workloads/terraform.tfstate"
  }

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
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

provider "kubernetes" {
  config_path = abspath("${path.root}/../../${local.cluster.kubeconfig_path}")
}

provider "helm" {
  kubernetes {
    config_path = abspath("${path.root}/../../${local.cluster.kubeconfig_path}")
  }
}
