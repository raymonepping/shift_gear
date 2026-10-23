output "vault_seal_release" {
  description = "Name of the seal Vault Helm release."
  value       = helm_release.vault_seal.name
}

output "vault_seal_namespace" {
  description = "Namespace of the seal Vault."
  value       = helm_release.vault_seal.namespace
}

output "vault_seal_address" {
  description = "Internal service address of the seal Vault."
  value       = "https://vault-seal.sg-vault-seal.svc:8200"
}

output "seal_agent_address" {
  description = "Internal service address of the seal agent (mTLS proxy)."
  value       = "https://seal-agent.sg-vault-seal.svc:8200"
}

output "vault_release" {
  description = "Name of the main Vault Helm release."
  value       = helm_release.vault.name
}

output "vault_namespace" {
  description = "Namespace of the main Vault cluster."
  value       = helm_release.vault.namespace
}

output "audit_collector" {
  description = "The audit collector: where Vault's socket device writes, and where the console reads."
  value = {
    ingest_address = "${kubernetes_service.audit_collector.metadata[0].name}.sg-app.svc:9090"
    read_url       = "http://${kubernetes_service.audit_collector.metadata[0].name}.sg-app.svc:8080"
  }
}

output "observability" {
  description = "Non-secret optional integration selection. None requires no telemetry backend or storage."
  value       = { metrics_backend = var.metrics_backend, audit_archive_enabled = var.audit_archive_enabled, storage_enabled = var.observability_storage_enabled }
  precondition {
    condition     = (!var.audit_archive_enabled && var.metrics_backend != "prometheus") || var.observability_storage_enabled
    error_message = "Archive or Prometheus requires protected storage; keep storage enabled when disabling runtime to preserve existing data."
  }
}
