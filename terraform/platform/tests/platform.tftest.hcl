# terraform/platform/tests/platform.tftest.hcl
# Shape-only tests for the platform root.
# Mock providers: no live Vault or cluster required.

mock_provider "vault" {}
mock_provider "http" {
  mock_data "http" {
    defaults = {
      status_code = 200
    }
  }
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
  target = data.vault_generic_secret.license
  values = {
    data_json = "{\"autoloaded\":{\"features\":[\"Transform Secrets Engine\",\"KMIP\"]}}"
  }
}

run "namespace_is_shift_gear" {
  command = plan

  assert {
    condition     = vault_namespace.shift_gear.path == "shift-gear"
    error_message = "Enterprise namespace must be named shift-gear"
  }
}

run "kv_has_prevent_destroy" {
  command = plan

  assert {
    condition     = vault_mount.kv.path == "kv"
    error_message = "kv mount must exist at path kv"
  }

  assert {
    condition     = vault_mount.kv.type == "kv"
    error_message = "kv mount type must be kv"
  }
}

run "app_data_key_non_exportable" {
  command = plan

  assert {
    condition     = vault_transit_secret_backend_key.app_data.exportable == false
    error_message = "app-data transit key must not be exportable"
  }

  assert {
    condition     = vault_transit_secret_backend_key.app_data.deletion_allowed == false
    error_message = "app-data transit key deletion must not be allowed"
  }
}

run "all_platform_policies_declared" {
  command = plan

  assert {
    condition = alltrue([
      for p in ["sg-engineer", "sg-operator", "sg-approver", "sg-auditor", "sg-vso", "sg-api", "sg-agent-demo"] :
      contains(var.platform_policies, p)
    ])
    error_message = "All seven platform policies must be declared."
  }
}

run "rejects_bootstrap_policy" {
  command = plan

  variables {
    platform_policies = ["sg-engineer", "sg-tf-platform"]
  }

  expect_failures = [var.platform_policies]
}

run "sg_ui_token_role_bound_to_pod_cidr" {
  command = plan

  assert {
    condition     = vault_token_auth_backend_role.sg_ui.role_name == "sg-ui"
    error_message = "Token role must be named sg-ui"
  }

  assert {
    condition     = vault_token_auth_backend_role.sg_ui.token_no_default_policy == true
    error_message = "sg-ui token role must set token_no_default_policy=true"
  }

  assert {
    condition     = contains(vault_token_auth_backend_role.sg_ui.token_bound_cidrs, "10.217.0.0/22")
    error_message = "sg-ui token role must be CIDR-bound to the pod network (lesson 31)"
  }
}

run "audit_device_is_file" {
  command = plan

  assert {
    condition     = vault_audit.file.type == "file"
    error_message = "Audit device must be of type file"
  }

  assert {
    condition     = vault_audit.file.options["file_path"] == "stdout"
    error_message = "Audit file_path must be stdout"
  }
}

override_data {
  target = data.terraform_remote_state.workloads
  values = {
    outputs = {
      audit_collector = {
        ingest_address = "sg-audit.sg-app.svc:9090"
        read_url       = "http://sg-audit.sg-app.svc:8080"
      }
    }
  }
}

run "socket_audit_device_targets_the_collector" {
  command = plan

  assert {
    condition     = vault_audit.socket.type == "socket" && vault_audit.socket.options["address"] == "sg-audit.sg-app.svc:9090"
    error_message = "The socket audit device must write to the collector the workloads root exports"
  }

  assert {
    condition     = vault_audit.file.type == "file"
    error_message = "The file audit device must stay: it keeps Vault serving while the collector restarts"
  }
}
