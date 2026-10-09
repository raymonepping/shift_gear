# terraform/workloads/tests/workloads.tftest.hcl
# Shape-only test for the workloads root.
# Uses mock providers to verify resource shapes without a real cluster.

mock_provider "kubernetes" {}
mock_provider "helm" {}

variables {
  vault_seal_chart_version = "0.30.0"
  vault_chart_version      = "0.30.0"
}

override_data {
  target = data.terraform_remote_state.infra
  values = {
    outputs = {
      cluster = {
        api_url         = "https://api.example.local:6443"
        apps_domain     = "apps.example.local"
        pod_cidr        = "10.217.0.0/22"
        kubeconfig_path = ".secrets/kube/config"
        ingress_ca_path = ".secrets/kube/ingress-ca.pem"
        registry_host   = "image-registry.openshift-image-registry.svc:5000"
      }
    }
  }
}

override_data {
  target = data.kubernetes_config_map_v1.sg_ca_identity
  values = {
    data = {
      "ca.pem" = "-----BEGIN CERTIFICATE-----\nMIIBmock\n-----END CERTIFICATE-----\n"
    }
  }
}

run "workloads_releases_exist" {
  command = plan

  assert {
    condition     = helm_release.vault_seal.name == "vault-seal"
    error_message = "vault-seal release must be named vault-seal"
  }

  assert {
    condition     = helm_release.vault_seal.namespace == "sg-vault-seal"
    error_message = "vault-seal must be in sg-vault-seal"
  }

  assert {
    condition     = helm_release.vault.name == "vault"
    error_message = "vault release must be named vault"
  }

  assert {
    condition     = helm_release.vault.namespace == "sg-vault"
    error_message = "vault must be in sg-vault"
  }

  assert {
    condition     = helm_release.vault_seal.wait == false
    error_message = "vault-seal must have wait=false"
  }

  assert {
    condition     = helm_release.vault.wait == false
    error_message = "vault must have wait=false"
  }
}

run "seal_agent_resources_exist" {
  command = plan

  assert {
    condition     = kubernetes_deployment.seal_agent.metadata[0].name == "seal-agent"
    error_message = "seal-agent Deployment must exist"
  }

  assert {
    condition     = kubernetes_service.seal_agent.spec[0].port[0].port == 8200
    error_message = "seal-agent Service must expose port 8200"
  }

  assert {
    condition     = kubernetes_cron_job_v1.seal_rotator.spec[0].schedule == "0 */6 * * *"
    error_message = "seal-rotator CronJob must run every 6 hours"
  }
}
