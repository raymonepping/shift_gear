# policies/bootstrap/sg-tf-platform.hcl
# sg-tf-platform — Terraform's token on the cluster (terraform/platform).
# Structure only: Enterprise namespace, mounts, ACL policies, token roles,
# audit devices. No auth methods, no identity, no secret data, no KV delete.

# ── Root-level (used to create the shift-gear namespace) ─────────────────────
path "sys/namespaces" {
  capabilities = ["list"]
}

path "sys/namespaces/shift-gear" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# ── Within shift-gear namespace (provider prefixes automatically) ─────────────
path "shift-gear/sys/mounts" {
  capabilities = ["read"]
}

path "shift-gear/sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete"]
}

# kv/ holds application secrets written by Ansible — Terraform may create and
# tune the mount, never delete it. The most-specific path wins (D11).
path "shift-gear/sys/mounts/kv" {
  capabilities = ["create", "read", "update"]
}

path "shift-gear/sys/mounts/kv/tune" {
  capabilities = ["read", "update"]
}

path "shift-gear/sys/remount" {
  capabilities = ["deny"]
}

path "shift-gear/sys/policies/acl" {
  capabilities = ["list"]
}

path "shift-gear/sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "shift-gear/sys/policy/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "shift-gear/auth/token/roles" {
  capabilities = ["list"]
}

path "shift-gear/auth/token/roles/*" {
  capabilities = ["create", "read", "update", "delete"]
}

# Transit key structure inside the namespace (never encrypt/decrypt).
path "shift-gear/transit/keys/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "shift-gear/transit/keys/+/config" {
  capabilities = ["create", "read", "update"]
}

# PKI mounts: root + intermediate CA structure (no CSR signing — that is Ansible).
path "shift-gear/pki/config/*" {
  capabilities = ["create", "read", "update"]
}

path "shift-gear/pki/root/generate/*" {
  capabilities = ["create", "update"]
}

# The root signs the intermediate's CSR (vault_pki_secret_backend_root_sign_intermediate).
path "shift-gear/pki/root/sign-intermediate" {
  capabilities = ["create", "update"]
}

# hashicorp/vault 5.x uses the issuer API: generate the root and the
# intermediate CSR, sign through an issuer, import the signed intermediate.
path "shift-gear/pki/issuers/generate/*" {
  capabilities = ["create", "update"]
}

path "shift-gear/pki/issuer/+/sign-intermediate" {
  capabilities = ["create", "update"]
}

path "shift-gear/pki-int/issuers/generate/*" {
  capabilities = ["create", "update"]
}

path "shift-gear/pki-int/issuers/import/*" {
  capabilities = ["create", "update"]
}

# Provider refresh of the PKI resources reads issuers and the CA certificate.
path "shift-gear/pki/issuers" {
  capabilities = ["list"]
}

path "shift-gear/pki/issuer/*" {
  capabilities = ["read"]
}

path "shift-gear/pki/cert/*" {
  capabilities = ["read"]
}

path "shift-gear/pki-int/issuers" {
  capabilities = ["list"]
}

path "shift-gear/pki-int/issuer/*" {
  capabilities = ["read"]
}

path "shift-gear/pki-int/cert/*" {
  capabilities = ["read"]
}

path "shift-gear/pki-int/config/*" {
  capabilities = ["create", "read", "update"]
}

path "shift-gear/pki-int/intermediate/*" {
  capabilities = ["create", "update"]
}

path "shift-gear/pki-int/roles/*" {
  capabilities = ["create", "read", "update", "delete"]
}

# Audit device (file to stdout). sudo required by the API.
path "sys/audit" {
  capabilities = ["read", "list", "sudo"]
}

path "sys/audit/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}

path "shift-gear/sys/license/status" {
  capabilities = ["read"]
}

path "sys/license/status" {
  capabilities = ["read"]
}

path "sys/health" {
  capabilities = ["read"]
}

# The Vault provider issues itself a short child token (kept for audit).
path "auth/token/create" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

# ── Never ────────────────────────────────────────────────────────────────────
# No tool can widen its own bootstrap access.
path "shift-gear/sys/policies/acl/sg-tf-*" {
  capabilities = ["deny"]
}

path "shift-gear/sys/policies/acl/sg-ansible-*" {
  capabilities = ["deny"]
}

path "shift-gear/sys/auth/*" {
  capabilities = ["deny"]
}

path "shift-gear/identity/*" {
  capabilities = ["deny"]
}

path "shift-gear/kv/*" {
  capabilities = ["deny"]
}
