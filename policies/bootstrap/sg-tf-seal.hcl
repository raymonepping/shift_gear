# policies/bootstrap/sg-tf-seal.hcl
# sg-tf-seal — Terraform's token on the seal Vault (terraform/seal).
# Structure only: the Transit mount and its one key, the two seal policies,
# the AppRole mount and its roles. It can never mint a secret-id.

path "sys/mounts" {
  capabilities = ["read"]
}

path "sys/mounts/transit" {
  capabilities = ["create", "read", "update"]
}

path "sys/mounts/transit/tune" {
  capabilities = ["read", "update"]
}

path "transit/keys/autounseal" {
  capabilities = ["create", "read", "update"]
}

path "transit/keys/autounseal/config" {
  capabilities = ["create", "read", "update"]
}

path "sys/policies/acl/autounseal" {
  capabilities = ["create", "read", "update", "delete"]
}

path "sys/policies/acl/sg-seal-rotator" {
  capabilities = ["create", "read", "update", "delete"]
}

path "sys/policy/autounseal" {
  capabilities = ["create", "read", "update", "delete"]
}

path "sys/policy/sg-seal-rotator" {
  capabilities = ["create", "read", "update", "delete"]
}

path "sys/auth" {
  capabilities = ["read"]
}

path "sys/auth/approle" {
  capabilities = ["create", "read", "update", "sudo"]
}

path "sys/mounts/auth/approle" {
  capabilities = ["read"]
}

path "sys/mounts/auth/approle/tune" {
  capabilities = ["read", "update"]
}

path "auth/approle/role/sg-seal-autounseal" {
  capabilities = ["create", "read", "update", "delete"]
}

path "auth/approle/role/sg-seal-rotator" {
  capabilities = ["create", "read", "update", "delete"]
}

# The provider reads role-ids into state as identifiers; never secret-ids.
path "auth/approle/role/+/role-id" {
  capabilities = ["read"]
}

path "auth/approle/role/+/secret-id" {
  capabilities = ["deny"]
}

# The Vault provider issues itself a short child token (kept for audit).
path "auth/token/create" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Never the bootstrap policies themselves — no tool can widen its own access.
path "sys/policies/acl/sg-tf-*" {
  capabilities = ["deny"]
}

path "sys/policies/acl/sg-ansible-*" {
  capabilities = ["deny"]
}
