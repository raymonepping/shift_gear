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

variable "collector_image" {
  description = "Reviewed immutable audit runtime image; override only for a controlled upgrade/rollback proof."
  type        = string
  default     = "registry.access.redhat.com/ubi9/nodejs-24-minimal@sha256:fe7301f641a4b16cfb36354623f2e1c3bb7838607321ce769e877ca201079a47"
  validation {
    condition     = can(regex("^registry\\.access\\.redhat\\.com/ubi9/nodejs-(22|24)-minimal@sha256:[a-f0-9]{64}$", var.collector_image))
    error_message = "Collector upgrade requires a reviewed Node 22/24 UBI digest."
  }
}

variable "ui_image" {
  description = "Built immutable image input; null permits first-build bootstrap only."
  type        = string
  default     = null
  validation {
    condition     = var.ui_image == null ? true : can(regex("@sha256:[a-f0-9]{64}$", var.ui_image))
    error_message = "Built image must use an immutable digest."
  }
}

variable "openldap_image" {
  description = "Built immutable image input; null permits first-build bootstrap only."
  type        = string
  default     = null
  validation {
    condition     = var.openldap_image == null ? true : can(regex("@sha256:[a-f0-9]{64}$", var.openldap_image))
    error_message = "Built image must use an immutable digest."
  }
}

variable "metrics_backend" {
  description = "Optional metrics integration: none (core lab), opentelemetry (preferred), or prometheus."
  type        = string
  default     = "none"
  validation {
    condition     = contains(["none", "opentelemetry", "prometheus"], var.metrics_backend)
    error_message = "Select none, opentelemetry or prometheus."
  }
}

variable "audit_archive_enabled" {
  description = "Opt into bounded audit metadata retention; the live ring needs no archive."
  type        = bool
  default     = false
}

variable "observability_storage_enabled" {
  description = "Provision protected observability PVCs. Keep true after use to retain data when disabling telemetry."
  type        = bool
  default     = false
}
