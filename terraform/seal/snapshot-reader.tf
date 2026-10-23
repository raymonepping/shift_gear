# Maintenance identity: download only, never restore. Values never enter state.
resource "vault_policy" "snapshot_reader" {
  name   = "sg-snapshot-reader"
  policy = <<-POLICY
    path "sys/storage/raft/snapshot" { capabilities = ["read"] }
    path "sys/storage/raft/snapshot-force" { capabilities = ["deny"] }
    path "sys/capabilities-self" { capabilities = ["update"] }
    path "auth/token/revoke-self" { capabilities = ["update"] }
  POLICY
}

resource "vault_token_auth_backend_role" "snapshot_reader" {
  role_name               = "sg-snapshot-reader"
  allowed_policies        = [vault_policy.snapshot_reader.name]
  orphan                  = false
  renewable               = false
  token_explicit_max_ttl  = 120
  token_no_default_policy = true
}
