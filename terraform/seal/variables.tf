variable "seal_token_ttl" {
  description = "TTL for the seal agent's AppRole token (seconds)."
  type        = number
  default     = 3600
}

variable "seal_token_max_ttl" {
  description = "Max TTL for the seal agent's AppRole token (seconds). 24 h cap."
  type        = number
  default     = 86400
}

variable "secret_id_ttl" {
  description = "TTL for AppRole secret-ids (seconds). 24 h — rotator runs every 6 h."
  type        = number
  default     = 86400
}

variable "lockout_threshold" {
  description = "AppRole lockout threshold (lesson 3 — bound AppRole failure rate)."
  type        = number
  default     = 3
}

variable "lockout_duration" {
  description = "AppRole lockout duration."
  type        = string
  default     = "30s"
}

variable "rotator_token_ttl" {
  description = "TTL for the rotator's AppRole token (short-lived; it runs once per job)."
  type        = number
  default     = 600
}
