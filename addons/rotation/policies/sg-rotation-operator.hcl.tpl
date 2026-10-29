# sg-rotation-operator — people who may *request* a rotation (and see history).
# They never read or write a value: a request is a custom-metadata patch
# (rotation_request) that the controller serves. 01_07's Sentinel EGP narrows
# the patch to that one key.
path "${mount}/metadata/${prefix}/*" {
  capabilities = ["read", "list", "patch"]
}
