# policies/platform/sg-approver.hcl
# Approvers: read KV for review, read ACL policies, no write access.
# Used for control-group approval flows (Vault Enterprise).
path "kv/data/shift-gear/*" {
  capabilities = ["read", "list"]
}
path "kv/metadata/shift-gear/*" {
  capabilities = ["read", "list"]
}
path "sys/policies/acl/*" {
  capabilities = ["read", "list"]
}
path "sys/control-group/request/*" {
  capabilities = ["create", "read", "update"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
