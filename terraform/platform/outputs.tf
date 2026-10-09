output "namespace" {
  description = "Fully-qualified path of the shift-gear Enterprise namespace."
  value       = vault_namespace.shift_gear.path_fq
}

output "mounts" {
  description = "Secret engine mounts owned by Terraform: path → type."
  value = {
    kv       = vault_mount.kv.path
    transit  = vault_mount.transit.path
    pki      = vault_mount.pki.path
    pki_int  = vault_mount.pki_int.path
    database = vault_mount.database.path
  }
}

output "transit_keys" {
  description = "Transit keys owned by Terraform."
  value = {
    app_data = "${vault_mount.transit.path}/${vault_transit_secret_backend_key.app_data.name}"
  }
}

output "pki_int_role" {
  description = "PKI intermediate role name for client certificate issuance."
  value       = vault_pki_secret_backend_role.internal_client.name
}

output "policies" {
  description = "ACL policy names owned by Terraform in the shift-gear namespace."
  value       = sort(tolist(var.platform_policies))
}

output "token_roles" {
  description = "Token role names owned by Terraform."
  value       = [vault_token_auth_backend_role.sg_ui.role_name]
}

output "audit_device" {
  description = "Type of the file audit device enabled by Terraform."
  value       = vault_audit.file.type
}

output "license_features" {
  description = "Enterprise licence features active on the cluster (metadata only — no licence string)."
  value       = sort(tolist(local.license_features))
}

output "skipped_engines" {
  description = "Licensed engines this root deliberately does not mount, and why (shown by the console)."
  value = [
    { path = "keymgmt/", reason = "Key Management needs a cloud KMS (AWS, Azure or GCP) to distribute keys to; this lab has none." },
    { path = "kmip/", reason = "KMIP clients speak raw TLS on port 5696; the OpenShift router only carries HTTP and SNI routes, so no client could reach it." },
    { path = "transform/", reason = "Tokenisation is a separate story; this lab shows encryption as a service with transit." },
  ]
}
