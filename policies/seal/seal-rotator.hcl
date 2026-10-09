# policies/seal/seal-rotator.hcl
# The rotator may only mint and destroy secret-ids of the seal agent's role.
# It cannot log in as the agent, cannot read the transit key, and cannot
# widen its own access (no sys/policies path).
path "auth/approle/role/sg-seal-autounseal/secret-id" {
  capabilities = ["update", "list"]
}

path "auth/approle/role/sg-seal-autounseal/secret-id-accessor/destroy" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
