# sg-rotation-auditor — read-only history and metadata for auditors.
path "${mount}/metadata/${prefix}/*" {
  capabilities = ["read", "list"]
}

# The natively rotated signing key (Transit, prompt 01_10): key metadata only
# (versions, auto_rotate_period; ed25519 returns public keys). No sign/verify.
path "transit/keys/session-signing" {
  capabilities = ["read"]
}
