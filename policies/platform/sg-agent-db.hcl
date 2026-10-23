# C03: one isolated dynamic consumer. No KV, other database role or structure access.
path "database/creds/agent-reader" {
  capabilities = ["read"]
}
