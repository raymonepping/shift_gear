# policies/platform/sg-operator.hcl
# Operators: read KV (no write), read health and HA, list audit, renew token.
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
