# policies/platform/sg-operator.hcl
# Operators: read KV, rotate the application config only, read health and HA,
# list audit and renew their own token. No structural administration.
path "kv/data/shift-gear/config/app-config" {
  capabilities = ["read", "update"]
}
path "kv/data/shift-gear/*" {
  capabilities = ["read", "list"]
}
path "kv/metadata/shift-gear/*" {
  capabilities = ["read", "list"]
}
path "sys/health" {
  capabilities = ["read"]
}
path "sys/ha-status" {
  capabilities = ["read"]
}
path "sys/audit" {
  capabilities = ["read", "list"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
