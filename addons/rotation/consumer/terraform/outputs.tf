output "namespace" {
  value = kubernetes_namespace.consumer.metadata[0].name
}

output "board_url" {
  value = "https://secure-door.${local.apps_domain}"
}

output "secret" {
  value = local.secret_id
}

output "policies" {
  value = [for p in vault_policy.party : p.name]
}

output "grace_seconds" {
  value = var.grace_seconds
}

output "render_interval" {
  value = var.render_interval
}

output "config_sha256" {
  value = local.checksum
}
