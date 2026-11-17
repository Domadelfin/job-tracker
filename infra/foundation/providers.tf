provider "aws" {
  region = var.region

  # Tags applied to every resource: makes cost tracking and cleanup easy
  # (Billing console -> filter by tag Project = job-tracker).
  default_tags {
    tags = {
      Project   = var.project
      Layer     = "foundation"
      ManagedBy = "terraform"
    }
  }
}
