output "namespace" {
  value = kubernetes_namespace.rotation.metadata[0].name
}

output "service" {
  value = "${kubernetes_service.controller.metadata[0].name}.${kubernetes_namespace.rotation.metadata[0].name}.svc:8080"
}

output "managed_prefix" {
  value = "${local.mount}/${local.prefix}"
}

output "secrets" {
  value = [for s in local.secrets : s.id]
}

output "policies" {
  value = [vault_policy.controller.name, vault_policy.operator.name, vault_policy.auditor.name]
}

output "config_sha256" {
  value = local.checksum
}

output "events_enabled" {
  value = var.events_enabled
}

output "sentinel_egp" {
  value = var.sentinel_enabled ? "sg-rotation-kv" : null
}
