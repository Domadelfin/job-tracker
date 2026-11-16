# ---------------------------------------------------------------------------
# Runtime layer: the BILLABLE resources (~$0.09/hr). Create for a session,
# then `terraform destroy` here. The foundation layer (VPC, SGs, IAM, ECR)
# stays and is never touched by this folder's destroy.
# ---------------------------------------------------------------------------

# Read the foundation layer's outputs (subnet IDs, security groups, roles...)
# straight from its state file, so no IDs are copied by hand.
data "terraform_remote_state" "foundation" {
  backend = "local"
  config = {
    path = "${path.module}/../foundation/terraform.tfstate"
  }
}

locals {
  f       = data.terraform_remote_state.foundation.outputs
  project = local.f.project
  sg      = local.f.security_group_ids
}

provider "aws" {
  region = local.f.region

  default_tags {
    tags = {
      Project   = local.f.project
      Layer     = "runtime"
      ManagedBy = "terraform"
    }
  }
}
