terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73"
    }
  }

  # State is stored locally in this folder (git-ignored). For a team you'd use
  # an S3 backend with locking; for a solo portfolio project local is fine.
}
