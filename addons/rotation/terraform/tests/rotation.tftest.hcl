# addons/rotation/terraform/tests/rotation.tftest.hcl
# Shape-only tests for the rotation add-on root. Mock providers: no cluster,
# no Vault.

mock_provider "vault" {}
mock_provider "kubernetes" {
  mock_data "kubernetes_config_map" {
    defaults = {
      data = { "ca.pem" = "-----BEGIN CERTIFICATE-----\nMOCK\n-----END CERTIFICATE-----\n" }
    }
  }
}

run "controller_pod_is_hardened" {
  command = plan

  assert {
    condition = alltrue([
      for c in kubernetes_deployment.controller.spec[0].template[0].spec[0].container :
      c.security_context[0].run_as_non_root && !c.security_context[0].allow_privilege_escalation &&
      c.security_context[0].read_only_root_filesystem && contains(c.security_context[0].capabilities[0].drop, "ALL")
    ])
    error_message = "Every container must be non-root, read-only, without privilege escalation, dropping ALL."
  }

  assert {
    condition = alltrue([
      for c in kubernetes_deployment.controller.spec[0].template[0].spec[0].container : c.resources[0].limits["memory"] != null
    ])
    error_message = "Every container needs a memory limit."
  }

  assert {
    condition = alltrue([
      for c in kubernetes_deployment.controller.spec[0].template[0].spec[0].container :
      can(regex("@sha256:[0-9a-f]{64}$", c.image))
    ])
    error_message = "Every image must be pinned by digest."
  }
}

run "controller_container_holds_no_token" {
  command = plan

  assert {
    condition = alltrue([
      for c in kubernetes_deployment.controller.spec[0].template[0].spec[0].container : c.name != "controller" || (
        alltrue([for e in c.env : !startswith(e.name, "VAULT_")]) &&
        alltrue([for m in c.volume_mount : m.name != "agent-sink"])
      )
    ])
    error_message = "The controller container must have no VAULT_* env and no access to the agent token sink."
  }
}

run "events_sidecar_is_optional" {
  command = plan

  variables {
    events_enabled = false
  }

  assert {
    condition     = length(kubernetes_deployment.controller.spec[0].template[0].spec[0].container) == 2
    error_message = "With events disabled the pod runs controller + vault-agent only."
  }
}

run "network_policies_are_scoped" {
  command = plan

  assert {
    condition     = kubernetes_network_policy.vault_from_rotation.metadata[0].namespace == "sg-vault" && kubernetes_network_policy.vault_from_rotation.metadata[0].labels["shift-gear/addon"] == "rotation"
    error_message = "The Vault allow must be an additive, add-on-labelled policy in sg-vault."
  }

  assert {
    condition     = kubernetes_network_policy.audit_from_rotation.spec[0].ingress[0].ports[0].port == "8080"
    error_message = "The audit allow admits only the collector's read port."
  }

  assert {
    condition     = length(kubernetes_network_policy.default_deny.spec[0].ingress) == 0
    error_message = "sg-rotation denies all ingress by default."
  }
}

run "policies_never_delete_managed_secrets" {
  command = plan

  assert {
    condition = alltrue([
      for p in [vault_policy.controller.policy, vault_policy.operator.policy, vault_policy.auditor.policy] :
      !strcontains(p, "\"delete\"") && !can(regex("path \"[^\"]*/(destroy|delete)/", p))
    ])
    error_message = "No add-on policy may delete or destroy anything."
  }

  assert {
    condition     = startswith(vault_policy.controller.name, "sg-rotation-") && startswith(vault_policy.operator.name, "sg-rotation-")
    error_message = "Add-on policies are named sg-rotation-*."
  }

  assert {
    condition     = !strcontains(vault_policy.controller.policy, "kv/data/shift-gear/config/app-config\" {\n  capabilities          = [\"read\"")
    error_message = "A watched path must never grant a data read."
  }
}

run "bad_config_is_refused" {
  command = plan

  variables {
    config_file = "tests/fixtures/loosening.yaml"
  }

  expect_failures = [terraform_data.config_contract]
}

run "sentinel_egp_is_rendered_from_the_config" {
  command = plan

  variables {
    sentinel_enabled = true
  }

  assert {
    condition     = vault_egp_policy.kv_rotation[0].enforcement_level == "hard-mandatory" && length(vault_egp_policy.kv_rotation[0].paths) == 2
    error_message = "The EGP governs the managed data and metadata paths, hard-mandatory."
  }

  assert {
    condition = alltrue([
      strcontains(vault_egp_policy.kv_rotation[0].policy, "\"rotation-controller\""),
      strcontains(vault_egp_policy.kv_rotation[0].policy, "\"sg-rotation\""),
      strcontains(vault_egp_policy.kv_rotation[0].policy, "\"api-key\": { \"min_length\": 32"),
      strcontains(vault_egp_policy.kv_rotation[0].policy, "rotation_request"),
    ])
    error_message = "The EGP must pin the controller's ServiceAccount, carry each type's policy and allow only rotation_request patches."
  }
}

run "a_non_application_owner_is_refused" {
  command = plan

  variables {
    config_file = "tests/fixtures/external-owner.yaml"
  }

  expect_failures = [terraform_data.config_contract]
}
