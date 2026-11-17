# One log group per service. Created here (not auto-created by ECS) so that:
#  - execution roles can be scoped to these exact ARNs
#  - retention is short, so logs never pile up into a cost
resource "aws_cloudwatch_log_group" "service" {
  for_each = local.services

  name              = "/ecs/${var.project}/${each.key}"
  retention_in_days = 3
}
