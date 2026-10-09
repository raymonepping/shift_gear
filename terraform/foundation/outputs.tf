output "namespaces" {
  description = "Names of the five Shift Gear namespaces (validation contract)."
  value = [
    kubernetes_namespace.sg_vault_seal.metadata[0].name,
    kubernetes_namespace.sg_vault.metadata[0].name,
    kubernetes_namespace.sg_identity.metadata[0].name,
    kubernetes_namespace.sg_workloads.metadata[0].name,
    kubernetes_namespace.sg_app.metadata[0].name,
  ]
}

output "apps_domain" {
  description = "Wildcard Route domain derived from the substrate contract."
  value       = local.apps_domain
}
