# ---------------------------------------------------------------------------
# IAM roles: one identity per job, each with only the permissions it needs.
#
#   <svc>-execution  used by ECS itself to pull the image + write logs (+ DB secret
#                    for backend, attached by the runtime layer once it exists)
#   <svc>-task       used by the application code at runtime: NO permissions,
#                    because neither service calls AWS APIs directly
#   (no CI role: see the note at the bottom of this file)
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# --- Trust policy shared by all ECS roles ----------------------------------
# "Only the ECS tasks service may assume this role, and only on behalf of my
# own project" (the aws:SourceAccount / SourceArn conditions prevent the
# confused-deputy problem).
data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ecs:${var.region}:${local.account_id}:*"]
    }
  }
}

# --- Execution roles (one per service) -------------------------------------

resource "aws_iam_role" "execution" {
  for_each = local.services

  name               = "${var.project}-${each.key}-execution"
  description        = "ECS agent for ${each.key}: pull its image, write its logs"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

data "aws_iam_policy_document" "execution" {
  for_each = local.services

  # GetAuthorizationToken can't be scoped to a repository (it returns a login
  # token for the registry), so AWS requires Resource "*" here.
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "PullOwnImageOnly"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [aws_ecr_repository.service[each.key].arn]
  }

  statement {
    sid       = "WriteOwnLogsOnly"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.service[each.key].arn}:*"]
  }
}

resource "aws_iam_role_policy" "execution" {
  for_each = local.services

  name   = "pull-image-and-write-logs"
  role   = aws_iam_role.execution[each.key].id
  policy = data.aws_iam_policy_document.execution[each.key].json
}

# --- Task roles (one per service, intentionally empty) ---------------------
# If a container were compromised, these credentials could do nothing in AWS.
# Add statements here only when the app code starts calling AWS (e.g. S3 uploads).

resource "aws_iam_role" "task" {
  for_each = local.services

  name               = "${var.project}-${each.key}-task"
  description        = "Runtime identity for ${each.key} app code - no AWS permissions needed"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_trust.json
}

# --- CI access: why there is no GitHub OIDC role ---------------------------
# The original design used GitHub Actions OIDC (keyless CI). This project's
# AWS-managed service control policy denies "iam:*Provider*", so an OIDC
# identity provider cannot be created (on Free or Paid plan). Rather than fall
# back to a long-lived IAM access key stored in GitHub, images are pushed from
# a developer machine using short-lived `aws login` credentials
# (see scripts/push-images.ps1). GitHub Actions still builds and tests images.
