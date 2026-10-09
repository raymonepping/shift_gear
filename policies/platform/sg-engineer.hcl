# policies/platform/sg-engineer.hcl
# Engineers: read and write KV secrets, encrypt/decrypt with the app-data
# transit key, read dynamic DB credentials, and issue short-lived client certs.
path "kv/data/shift-gear/*" {
  capabilities = ["create", "read", "update", "list"]
}
path "kv/metadata/shift-gear/*" {
  capabilities = ["read", "list"]
}
path "transit/encrypt/app-data" {
  capabilities = ["create", "update"]
}
path "transit/decrypt/app-data" {
  capabilities = ["create", "update"]
}
path "database/creds/demo-reader" {
  capabilities = ["read"]
}
path "pki-int/issue/internal-client" {
  capabilities = ["create", "update"]
}
