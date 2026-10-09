# policies/bootstrap/sg-ansible-platform.hcl
# sg-ansible-platform — Ansible's token on the cluster (identity, configure,
# validate). Configuration only: auth methods, identity groups/aliases,
# KV seeds, DB connection, tokens through Terraform-made roles.
# It never creates a mount, writes a policy, or deletes anything structural.

# ── Auth methods (within shift-gear namespace) ────────────────────────────────
path "sys/auth" {
  capabilities = ["read"]
}

path "shift-gear/sys/auth" {
  capabilities = ["read"]
}

path "shift-gear/sys/auth/oidc" {
  capabilities = ["create", "read", "update", "sudo"]
}

path "shift-gear/sys/auth/jwt" {
  capabilities = ["create", "read", "update", "sudo"]
}

path "shift-gear/sys/auth/ldap" {
  capabilities = ["create", "read", "update", "sudo"]
}

path "shift-gear/sys/auth/kubernetes" {
  capabilities = ["create", "read", "update", "sudo"]
}

path "shift-gear/sys/auth/approle" {
  capabilities = ["create", "read", "update", "sudo"]
}

path "shift-gear/sys/auth/cert" {
  capabilities = ["create", "read", "update", "sudo"]
}

path "shift-gear/auth/oidc/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "shift-gear/auth/jwt/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "shift-gear/auth/ldap/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "shift-gear/auth/kubernetes/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "shift-gear/auth/approle/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "shift-gear/auth/cert/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# ── Identity (within shift-gear namespace) ────────────────────────────────────
path "shift-gear/identity/group" {
  capabilities = ["create", "update"]
}

path "shift-gear/identity/group/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "shift-gear/identity/group-alias" {
  capabilities = ["create", "update"]
}

path "shift-gear/identity/group-alias/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "shift-gear/identity/lookup/group" {
  capabilities = ["update"]
}

# ── KV secrets (application seeds within shift-gear) ─────────────────────────
path "shift-gear/kv/data/shift-gear/*" {
  capabilities = ["create", "read", "update"]
}

path "shift-gear/kv/metadata/shift-gear/*" {
  capabilities = ["read", "list"]
}

# ── Database connection management ───────────────────────────────────────────
path "shift-gear/database/config/*" {
  capabilities = ["create", "read", "update"]
}

path "shift-gear/database/roles/*" {
  capabilities = ["create", "read", "update", "delete"]
}

path "shift-gear/database/rotate-root/*" {
  capabilities = ["update"]
}

# ── Tokens only through Terraform-made roles ─────────────────────────────────
path "shift-gear/auth/token/create/sg-*" {
  capabilities = ["update"]
}

path "shift-gear/auth/token/lookup" {
  capabilities = ["update"]
}

path "shift-gear/auth/token/lookup-accessor" {
  capabilities = ["update"]
}

# ── Read-only evidence for validation ────────────────────────────────────────
path "shift-gear/sys/policies/acl/*" {
  capabilities = ["read", "list"]
}

path "shift-gear/sys/mounts" {
  capabilities = ["read"]
}

path "sys/namespaces" {
  capabilities = ["list"]
}

path "shift-gear/auth/token/roles/*" {
  capabilities = ["read"]
}

# Validation reads cluster status (read-only).
path "sys/ha-status" {
  capabilities = ["read"]
}

path "sys/storage/raft/configuration" {
  capabilities = ["read"]
}

path "sys/license/status" {
  capabilities = ["read"]
}

path "shift-gear/sys/license/status" {
  capabilities = ["read"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}

# ── Never ────────────────────────────────────────────────────────────────────
path "shift-gear/sys/mounts/*" {
  capabilities = ["deny"]
}

path "shift-gear/sys/namespaces/*" {
  capabilities = ["deny"]
}

path "shift-gear/sys/policy/*" {
  capabilities = ["deny"]
}
