variable "image_tag" {
  description = "Image tag (git short SHA) to deploy for both services, e.g. d1606b9. Printed by scripts/push-images.ps1."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{7}$", var.image_tag))
    error_message = "image_tag must be a 7-character git short SHA (clean builds only, not -dirty tags)."
  }
}

variable "use_spot" {
  description = "Run tasks on Fargate Spot (~70% cheaper, may be interrupted with 2 min notice). Fine for demos."
  type        = bool
  default     = true
}

variable "db_instance_class" {
  description = "Smallest burstable Graviton instance; plenty for a demo."
  type        = string
  default     = "db.t4g.micro"
}

variable "nat_instance_type" {
  description = <<-EOT
    Tiny Graviton (ARM) instance doing NAT. Must be Free-plan eligible: the Free
    plan rejects other types (t4g.nano fails). List allowed types with:
    aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true
  EOT
  type        = string
  default     = "t4g.micro"
}
