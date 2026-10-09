# policies/seal/autounseal.hcl
# Transit auto-unseal for the Shift Gear cluster: use the one key, nothing
# else. Held by the seal agent's AppRole token (sg-seal-autounseal).
path "transit/encrypt/autounseal" {
  capabilities = ["update"]
}

path "transit/decrypt/autounseal" {
  capabilities = ["update"]
}

path "transit/keys/autounseal" {
  capabilities = ["read"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
