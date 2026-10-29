variable "config_file" {
  description = "The declarative rotation configuration (types, generators, schedules, policies, secrets)."
  type        = string
  default     = "../rotation.yaml"
}

variable "python_image" {
  description = "UBI 9 Python 3.12 minimal, arm64, pinned by digest (ASSESSMENT P8). The controller is stdlib-only, so no build."
  type        = string
  default     = "registry.access.redhat.com/ubi9/python-312-minimal@sha256:6e8175c7a7d288ebeddd1b929def954e6d9e46a533a21641e6eae562b3c9a081"

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.python_image))
    error_message = "python_image must be pinned by digest."
  }
}

variable "vault_image" {
  description = "Same Vault Enterprise image the core agent pods use (make rotation-validate asserts it matches terraform/workloads)."
  type        = string
  default     = "docker.io/hashicorp/vault-enterprise:2.1.0-ent@sha256:12c3ac1469d11da17747927128ed11bce825a012d3ce13b066d0442d0105df0a"

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.vault_image))
    error_message = "vault_image must be pinned by digest."
  }
}

variable "namespace" {
  description = "Kubernetes namespace of the add-on."
  type        = string
  default     = "sg-rotation"
}

variable "vault_namespace" {
  description = "Vault namespace that holds the kv mount."
  type        = string
  default     = "shift-gear"
}

variable "events_enabled" {
  description = "Run the vault-events sidecar (Vault event notifications). False = the controller polls only."
  type        = bool
  default     = true
}

variable "test_mode" {
  description = "Enables controller test hooks (rotation-test only). Never true outside a test run."
  type        = bool
  default     = false
}

variable "test_pause_after_write" {
  description = "Seconds the controller sleeps between a write and its history record (rotation-test s08 crash window). Honoured only with test_mode."
  type        = number
  default     = 0
}

variable "sentinel_enabled" {
  description = "Enforcement layer 3: the Sentinel EGP sg-rotation-kv (ADR D18; needs the sg-tf-platform egp/sg-rotation-* grant and a Sentinel licence)."
  type        = bool
  default     = true
}
