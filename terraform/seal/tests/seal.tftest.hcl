# terraform/seal/tests/seal.tftest.hcl
# Shape-only test for the seal root.
# Uses mock providers to verify the Transit mount and AppRole shapes
# without a real Vault; CIDRs come from the infra contract mock.

mock_provider "vault" {}

variables {
  seal_token_ttl     = 3600
  seal_token_max_ttl = 86400
  secret_id_ttl      = 86400
  rotator_token_ttl  = 600
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

run "transit_mount_is_prevent_destroy" {
  command = plan

  assert {
    condition     = vault_mount.transit.path == "transit"
    error_message = "Transit mount path must be 'transit'"
  }

  assert {
    condition     = vault_mount.transit.type == "transit"
    error_message = "Transit mount type must be 'transit'"
  }
}

run "autounseal_key_non_exportable" {
  command = plan

  assert {
    condition     = vault_transit_secret_backend_key.autounseal.exportable == false
    error_message = "autounseal key must not be exportable"
  }

  assert {
    condition     = vault_transit_secret_backend_key.autounseal.deletion_allowed == false
    error_message = "autounseal key deletion must not be allowed"
  }
}

run "approle_roles_bound_to_pod_cidr" {
  command = plan

  assert {
    condition     = contains(vault_approle_auth_backend_role.autounseal.token_bound_cidrs, "10.217.0.0/22")
    error_message = "seal-autounseal role must be CIDR-bound to the pod network"
  }

  assert {
    condition     = vault_approle_auth_backend_role.autounseal.role_name == "sg-seal-autounseal"
    error_message = "Autounseal role must be named sg-seal-autounseal"
  }

  assert {
    condition     = vault_approle_auth_backend_role.rotator.role_name == "sg-seal-rotator"
    error_message = "Rotator role must be named sg-seal-rotator"
  }
}
