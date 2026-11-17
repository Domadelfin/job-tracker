# ---------------------------------------------------------------------------
# ECR: private Docker image registry, one repository per service.
# Storage is $0.10/GB-month; the lifecycle policy keeps this to cents.
# ---------------------------------------------------------------------------

locals {
  services = toset(["frontend", "backend"])
}

resource "aws_ecr_repository" "service" {
  for_each = local.services

  name = "${var.project}/${each.key}"

  # A pushed tag (we'll use the git commit SHA) can never be overwritten, so a
  # tag always identifies exactly one build.
  image_tag_mutability = "IMMUTABLE"

  # Free basic scan for known CVEs in OS packages on every push.
  image_scanning_configuration {
    scan_on_push = true
  }

  # Allow `terraform destroy` even when images exist (fine for a portfolio project;
  # in production you'd usually protect this).
  force_delete = true
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each   = aws_ecr_repository.service
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged images (leftovers from re-pushes) after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the 5 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = { type = "expire" }
      },
    ]
  })
}
