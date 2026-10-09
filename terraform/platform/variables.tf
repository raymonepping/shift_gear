variable "platform_policies" {
  description = "ACL policies Terraform owns in the shift-gear namespace (files under policies/platform/). Never the sg-tf-*/sg-ansible-* bootstrap policies."
  type        = set(string)
  default     = ["sg-engineer", "sg-operator", "sg-approver", "sg-auditor", "sg-vso", "sg-api", "sg-agent-demo"]

  validation {
    condition     = alltrue([for p in var.platform_policies : !startswith(p, "sg-tf-") && !startswith(p, "sg-ansible-")])
    error_message = "Bootstrap policies belong to Ansible; Terraform must never manage them."
  }
}
