# terraform/infra/variables.tf — the only substrate-specific inputs.
# Everything else is discovered from the running cluster.

variable "kubeconfig_path" {
  description = "Path to the kubeconfig file for the OpenShift cluster."
  type        = string
  default     = ".secrets/kube/config"

  validation {
    condition     = length(var.kubeconfig_path) > 0
    error_message = "kubeconfig_path must not be empty."
  }
}

variable "api_url" {
  description = "OpenShift cluster API endpoint (e.g. https://api.crc.testing:6443)."
  type        = string
  default     = "https://api.crc.testing:6443"

  validation {
    condition     = can(regex("^https://", var.api_url))
    error_message = "api_url must start with https://."
  }
}
