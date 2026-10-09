# policies/platform/sg-vso.hcl
# Vault Secrets Operator service account token policy.
# Read config secrets and DB credentials. Renew and revoke own token only.
path "kv/data/shift-gear/config/*" {
  capabilities = ["read"]
}
path "kv/metadata/shift-gear/config/*" {
  capabilities = ["read", "list"]
}
path "database/creds/demo-reader" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
path "auth/token/revoke-self" {
  capabilities = ["update"]
}
