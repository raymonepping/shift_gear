# terraform/foundation/tests/namespaces.tftest.hcl
# Asserts namespace names follow the sg-* convention.
# Uses mock providers — no running cluster required.

mock_provider "kubernetes" {}

run "namespace_names_match_pattern" {
  command = plan

  assert {
    condition = alltrue([
      for ns in output.namespaces :
      can(regex("^sg-[a-z0-9-]+$", ns))
    ])
    error_message = "All namespace names must match ^sg-[a-z0-9-]+$"
  }

  assert {
    condition     = length(output.namespaces) == 5
    error_message = "Expected exactly 5 Shift Gear namespaces"
  }
}

run "seal_observer_is_named_get_only" {
  command = plan
  assert {
    condition = (
      kubernetes_role_v1.ui_seal_observer.metadata[0].namespace == "sg-vault-seal" &&
      length(kubernetes_role_v1.ui_seal_observer.rule) == 1 &&
      toset(kubernetes_role_v1.ui_seal_observer.rule[0].resources) == toset(["deployments"]) &&
      toset(kubernetes_role_v1.ui_seal_observer.rule[0].resource_names) == toset(["seal-agent"]) &&
      toset(kubernetes_role_v1.ui_seal_observer.rule[0].verbs) == toset(["get"]) &&
      kubernetes_role_binding_v1.ui_seal_observer.subject[0].name == "sg-ui-observer" &&
      kubernetes_role_binding_v1.ui_seal_observer.subject[0].namespace == "sg-app"
    )
    error_message = "Seal observer must only GET the named Agent Deployment as the UI identity"
  }
}
