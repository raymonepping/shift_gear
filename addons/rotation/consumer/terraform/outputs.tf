output "namespace" {
  value = kubernetes_namespace.consumer.metadata[0].name
}

output "board_url" {
  value = "https://secure-door.${local.apps_domain}"
}

output "secret" {
  value = local.secret_id
}

output "policy" {
  value = vault_policy.consumer.name
}

output "render_interval" {
  value = var.render_interval
}

output "config_sha256" {
  value = local.checksum
}
