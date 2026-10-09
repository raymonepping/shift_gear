variable "vault_seal_chart_version" {
  description = "Vault Helm chart version for the seal Vault release."
  type        = string
  default     = "0.30.0"
}

variable "vault_chart_version" {
  description = "Vault Helm chart version for the main cluster release."
  type        = string
  default     = "0.30.0"
}
