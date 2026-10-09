# terraform/infra/tests/contract.tftest.hcl
# Asserts the shape of the cluster output contract.
# Uses mock providers — no running cluster required.
# Run: scripts/tf-run.sh infra test

mock_provider "kubernetes" {
  mock_data "kubernetes_resource" {
    defaults = {
      object = {
        spec = {
          domain = "apps-crc.testing"
        }
        status = {
          clusterNetwork = [
            { cidr = "10.217.0.0/22" }
          ]
        }
      }
    }
  }
  mock_data "kubernetes_config_map_v1" {
    defaults = {
      data = {
        "ca-bundle.crt" = "-----BEGIN CERTIFICATE-----\nMOCK\n-----END CERTIFICATE-----\n"
      }
    }
  }
}

mock_provider "local" {}

variables {
  kubeconfig_path = ".secrets/kube/config"
  api_url         = "https://api.crc.testing:6443"
}

run "contract_shape" {
  command = plan

  assert {
    condition     = output.cluster.api_url == "https://api.crc.testing:6443"
    error_message = "api_url must equal var.api_url"
  }

  assert {
    condition     = length(output.cluster.apps_domain) > 0
    error_message = "apps_domain must be non-empty"
  }

  assert {
    condition     = !can(regex("https?://", output.cluster.apps_domain))
    error_message = "apps_domain must not contain a scheme (no https://)"
  }

  assert {
    condition     = length(output.cluster.pod_cidr) > 0
    error_message = "pod_cidr must be non-empty"
  }

  assert {
    condition     = length(output.cluster.kubeconfig_path) > 0
    error_message = "kubeconfig_path must be non-empty"
  }

  assert {
    condition     = length(output.cluster.ingress_ca_path) > 0
    error_message = "ingress_ca_path must be non-empty"
  }

  assert {
    condition     = length(output.cluster.registry_host) > 0
    error_message = "registry_host must be non-empty"
  }
}
