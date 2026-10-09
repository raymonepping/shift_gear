# policies/platform/sg-api.hcl
# Shift Gear API server (BFF/Express). Reads health, HA status, and identity
# metadata for the evidence dashboard. Issues wrapped AppRole secret-ids.
path "sys/health" {
  capabilities = ["read"]
}
path "sys/ha-status" {
  capabilities = ["read"]
}
path "sys/policies/acl/*" {
  capabilities = ["read", "list"]
}
path "identity/entity/id/*" {
  capabilities = ["read", "list"]
}
path "identity/group/id/*" {
  capabilities = ["read", "list"]
}
path "auth/approle/role/sg-automation/secret-id" {
  capabilities      = ["create", "update"]
  min_wrapping_ttl  = "1s"
  max_wrapping_ttl  = "2m"
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
