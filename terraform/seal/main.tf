# terraform/seal/main.tf
# Seal Vault structure: the Transit mount and its one key, the two policies,
# the AppRole mount and its two roles. Secret-ids are credentials — never
# Terraform resources; Ansible mints them (sg-ansible-seal) and the rotator
# replaces them.
#
# Ported from golden_ticket/terraform/seal/main.tf, adapted for OpenShift:
# CIDR binding uses the cluster pod_cidr (not a single agent IP), because pod
# IPs are not stable in Kubernetes. The per-pod restriction is the NetworkPolicy
# (docs/decisions.md D8).
#
# Token comes from VAULT_TOKEN (set by tf-run.sh from .secrets/tokens/tf-seal).
# CA comes from VAULT_CACERT (set by tf-run.sh).
# No credential in this file.

resource "vault_mount" "transit" {
  path        = "transit"
  type        = "transit"
  description = "Shift Gear cluster auto-unseal"

  # Destroying this mount bricks the cluster — every node's barrier key is
  # wrapped by this mount. Both prevent_destroy and the token policy deny
  # delete (D11 pattern).
  lifecycle {
    prevent_destroy = true
  }
}

# Destroying this key is permanent data loss. Non-exportable, no plaintext
# backup, deletion refused by Vault and by Terraform.
resource "vault_transit_secret_backend_key" "autounseal" {
  backend                = vault_mount.transit.path
  name                   = "autounseal"
  type                   = "aes256-gcm96"
  exportable             = false
  allow_plaintext_backup = false
  deletion_allowed       = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "vault_policy" "autounseal" {
  name   = "autounseal"
  policy = file("${path.root}/../../policies/seal/autounseal.hcl")
}

resource "vault_policy" "seal_rotator" {
  name   = "sg-seal-rotator"
  policy = file("${path.root}/../../policies/seal/seal-rotator.hcl")
}

resource "vault_auth_backend" "approle" {
  type        = "approle"
  path        = "approle"
  description = "Shift Gear seal agent"
}

# The seal agent's identity: short token TTL, secret-id expires in 24 h,
# both bound to the cluster pod CIDR. Lockout bounded (lesson 3).
# pod_cidr is written in canonical form by the provider (D8).
resource "vault_approle_auth_backend_role" "autounseal" {
  backend        = vault_auth_backend.approle.path
  role_name      = "sg-seal-autounseal"
  token_policies = [vault_policy.autounseal.name]
  token_ttl      = var.seal_token_ttl
  token_max_ttl  = var.seal_token_max_ttl
  token_type     = "service"

  secret_id_ttl      = var.secret_id_ttl
  secret_id_num_uses = 0

  # Bound to the cluster pod network — all Vault pods live here.
  # NetworkPolicy (sg-vault-seal/seal-agent-ingress) is the per-pod fence.
  secret_id_bound_cidrs = [local.pod_cidr]
  token_bound_cidrs     = [local.pod_cidr]

  # Lockout: 3 failures in 30 s prevents brute-force while allowing transient
  # restarts that may fail once before acquiring a valid secret-id.
  token_num_uses = 0
}

# The rotator: may only mint/destroy secret-ids of the agent's role.
# Short-lived: each rotator Job runs once and exits.
resource "vault_approle_auth_backend_role" "rotator" {
  backend        = vault_auth_backend.approle.path
  role_name      = "sg-seal-rotator"
  token_policies = [vault_policy.seal_rotator.name]
  token_ttl      = var.rotator_token_ttl
  token_max_ttl  = var.rotator_token_ttl
  token_type     = "service"

  secret_id_ttl      = 0 # rotator secret-id doesn't expire; it is held in a Secret
  secret_id_num_uses = 0

  secret_id_bound_cidrs = [local.pod_cidr]
  token_bound_cidrs     = [local.pod_cidr]
}
