# policies/bootstrap/sg-ansible-seal.hcl
# sg-ansible-seal — Ansible's token on the seal Vault (ansible/agent.yml,
# validation). Configuration only: read role-ids, mint/destroy secret-ids.
# No mounts, no policies, no roles.

path "auth/approle/role/sg-seal-autounseal/role-id" {
  capabilities = ["read"]
}

path "auth/approle/role/sg-seal-rotator/role-id" {
  capabilities = ["read"]
}

path "auth/approle/role/sg-seal-autounseal/secret-id" {
  capabilities = ["update", "list"]
}

path "auth/approle/role/sg-seal-rotator/secret-id" {
  capabilities = ["update", "list"]
}

path "auth/approle/role/+/secret-id-accessor/lookup" {
  capabilities = ["update"]
}

path "auth/approle/role/+/secret-id-accessor/destroy" {
  capabilities = ["update"]
}

path "auth/approle/role/+/secret-id/lookup" {
  capabilities = ["update"]
}

# Validation: the key exists (never its material).
path "transit/keys/autounseal" {
  capabilities = ["read"]
}

path "sys/mounts" {
  capabilities = ["read"]
}

path "sys/auth" {
  capabilities = ["read"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Never mounts, policies, or roles — those are Terraform's.
path "sys/policies/acl/*" {
  capabilities = ["deny"]
}

path "sys/mounts/*" {
  capabilities = ["deny"]
}
