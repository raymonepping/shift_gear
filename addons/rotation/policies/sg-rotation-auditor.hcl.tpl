# sg-rotation-auditor — read-only history and metadata for auditors.
path "${mount}/metadata/${prefix}/*" {
  capabilities = ["read", "list"]
}
