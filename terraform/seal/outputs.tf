output "autounseal_role_name" {
  description = "AppRole role name for the seal agent."
  value       = vault_approle_auth_backend_role.autounseal.role_name
}

output "rotator_role_name" {
  description = "AppRole role name for the seal rotator."
  value       = vault_approle_auth_backend_role.rotator.role_name
}

output "transit_mount_path" {
  description = "Path of the Transit mount on the seal Vault."
  value       = vault_mount.transit.path
}

output "autounseal_key_name" {
  description = "Name of the transit auto-unseal key (non-exportable)."
  value       = vault_transit_secret_backend_key.autounseal.name
}
