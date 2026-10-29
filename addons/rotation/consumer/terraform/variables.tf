variable "namespace" {
  description = "Kubernetes namespace of the Secure Door consumer."
  type        = string
  default     = "sg-rotation-consumer"
}

variable "vault_namespace" {
  description = "Vault namespace that holds the kv mount."
  type        = string
  default     = "shift-gear"
}

variable "secret_path" {
  description = "The watched managed secret, mount-relative (a dedicated secret without the usage strategy — see the README)."
  type        = string
  default     = "shift-gear/rotation/api-key/secure-door"
}

variable "render_interval" {
  description = "Vault Agent template_config.static_secret_render_interval (consumer setting; does not change the rotation schedule)."
  type        = string
  default     = "5s"
}

variable "poll_seconds" {
  description = "How often the consumer reads the rendered file."
  type        = number
  default     = 1
}

variable "request_seconds" {
  description = "How often the client asks the verifier to open the door."
  type        = number
  default     = 1
}

variable "grace_seconds" {
  description = "Verifier cut-over: 0 = strict (the previous version is retired the moment a new one is adopted); > 0 = the previous version stays accepted this long."
  type        = number
  default     = 30
  validation {
    condition     = var.grace_seconds >= 0 && var.grace_seconds <= 3600
    error_message = "grace_seconds must be between 0 and 3600."
  }
}

variable "stale_after_seconds" {
  description = "Vault unreachable this long turns last-known-good into stale."
  type        = number
  default     = 60
}

variable "python_image" {
  description = "UBI 9 Python 3.12 minimal, arm64, pinned (same as the rotation controller)."
  type        = string
  default     = "registry.access.redhat.com/ubi9/python-312-minimal@sha256:6e8175c7a7d288ebeddd1b929def954e6d9e46a533a21641e6eae562b3c9a081"
  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.python_image))
    error_message = "python_image must be pinned by digest."
  }
}

variable "node_image" {
  description = "UBI 9 Node.js 24 minimal, arm64, pinned (same as the audit collector)."
  type        = string
  default     = "registry.access.redhat.com/ubi9/nodejs-24-minimal@sha256:fe7301f641a4b16cfb36354623f2e1c3bb7838607321ce769e877ca201079a47"
  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.node_image))
    error_message = "node_image must be pinned by digest."
  }
}

variable "vault_image" {
  description = "The core's pinned Vault Enterprise image (Agent and probe)."
  type        = string
  default     = "docker.io/hashicorp/vault-enterprise:2.1.0-ent@sha256:12c3ac1469d11da17747927128ed11bce825a012d3ce13b066d0442d0105df0a"
  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.vault_image))
    error_message = "vault_image must be pinned by digest."
  }
}
