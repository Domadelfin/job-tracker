variable "project" {
  description = "Name prefix for all resources"
  type        = string
  default     = "job-tracker"
}

variable "region" {
  description = "Your project's selected Region (AWS Settings > View all projects > Overview > Additional Info > Region)"
  type        = string
  default     = "ap-southeast-2"
}

variable "vpc_cidr" {
  description = "Address range for the VPC. /16 = 65,536 addresses, split into /24 subnets below."
  type        = string
  default     = "10.0.0.0/16"
}
