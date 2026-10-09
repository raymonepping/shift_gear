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
