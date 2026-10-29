# sg-rotation-operator — people who may *request* a rotation (and see history).
# They never read or write a value: a request is a custom-metadata patch
# (rotation_request) that the controller serves. 01_07's Sentinel EGP narrows
# the patch to that one key.
path "${mount}/metadata/${prefix}/*" {
  capabilities = ["read", "list", "patch"]
}

# The natively rotated signing key (Transit, prompt 01_10): key metadata only
# (versions, auto_rotate_period; ed25519 returns public keys). No sign/verify.
path "transit/keys/session-signing" {
  capabilities = ["read"]
}
