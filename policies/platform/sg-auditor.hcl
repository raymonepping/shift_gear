# policies/platform/sg-auditor.hcl
# Auditors: read audit device list, health, HA status, identity metadata. Read only.
path "sys/audit" {
  capabilities = ["read", "list"]
}
path "sys/health" {
  capabilities = ["read"]
}
path "sys/ha-status" {
  capabilities = ["read"]
}
path "sys/storage/raft/configuration" {
  capabilities = ["read"]
}
path "identity/entity/id/*" {
  capabilities = ["read", "list"]
}
path "identity/group/id/*" {
  capabilities = ["read", "list"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
