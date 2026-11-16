# ---------------------------------------------------------------------------
# ECS on Fargate: a cluster, one task definition ("recipe") and one service
# ("keep N copies running behind the ALB") per app.
# ---------------------------------------------------------------------------

resource "aws_ecs_cluster" "main" {
  name = local.project

  setting {
    name  = "containerInsights"
    value = "disabled" # extra CloudWatch metrics cost money; logs are enough here
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

locals {
  capacity_provider = var.use_spot ? "FARGATE_SPOT" : "FARGATE"
  log_options = {
    for svc in ["frontend", "backend"] : svc => {
      "awslogs-group"         = local.f.log_group_names[svc]
      "awslogs-region"        = local.f.region
      "awslogs-stream-prefix" = svc
    }
  }
  db_secret_arn = aws_db_instance.main.master_user_secret[0].secret_arn
}

# --- Task definitions --------------------------------------------------------

resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.project}-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # each task gets its own network interface + security group
  cpu                      = 256      # 0.25 vCPU
  memory                   = 512      # MiB
  execution_role_arn       = local.f.execution_role_arns["backend"]
  task_role_arn            = local.f.task_role_arns["backend"]

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64" # images are built for linux/amd64
  }

  container_definitions = jsonencode([{
    name                   = "backend"
    image                  = "${local.f.ecr_repository_urls["backend"]}:${var.image_tag}"
    essential              = true
    readonlyRootFilesystem = true # the API never writes to disk
    stopTimeout            = 15   # time for graceful SIGTERM shutdown

    portMappings = [{ containerPort = 4000, protocol = "tcp" }]

    environment = [
      { name = "PORT", value = "4000" },
      { name = "DB_HOST", value = aws_db_instance.main.address },
      { name = "DB_PORT", value = tostring(aws_db_instance.main.port) },
      { name = "DB_NAME", value = aws_db_instance.main.db_name },
      { name = "DB_SSL", value = "true" },
      { name = "DB_SSL_CA_PATH", value = "/app/certs/rds-global-bundle.pem" },
    ]

    # Injected by ECS (execution role) from Secrets Manager at container start.
    # Format: <secret ARN>:<json key>:<version stage>:<version id>
    secrets = [
      { name = "DB_USER", valueFrom = "${local.db_secret_arn}:username::" },
      { name = "DB_PASSWORD", valueFrom = "${local.db_secret_arn}:password::" },
    ]

    logConfiguration = { logDriver = "awslogs", options = local.log_options["backend"] }
  }])

  # The execution role must be able to read the secret before tasks start.
  depends_on = [aws_iam_role_policy.backend_read_db_secret]
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${local.project}-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = local.f.execution_role_arns["frontend"]
  task_role_arn            = local.f.task_role_arns["frontend"]

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name        = "frontend"
    image       = "${local.f.ecr_repository_urls["frontend"]}:${var.image_tag}"
    essential   = true
    stopTimeout = 15
    # Root filesystem stays writable: Next.js writes its cache under .next/ at runtime.

    portMappings = [{ containerPort = 3000, protocol = "tcp" }]

    logConfiguration = { logDriver = "awslogs", options = local.log_options["frontend"] }
  }])
}

# --- Services --------------------------------------------------------------

resource "aws_ecs_service" "backend" {
  name            = "backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = local.capacity_provider
    weight            = 1
  }

  network_configuration {
    subnets          = local.f.private_app_subnet_ids
    security_groups  = [local.sg.backend]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 4000
  }

  health_check_grace_period_seconds = 60 # time to run the schema migration on first start

  # Roll back automatically if a new version never becomes healthy.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  wait_for_steady_state = true # `apply` only finishes once tasks are healthy

  depends_on = [
    aws_lb_listener_rule.api,
    aws_route.private_app_to_nat, # tasks need the NAT to reach ECR/Secrets Manager/Logs
    aws_ecs_cluster_capacity_providers.main,
  ]
}

resource "aws_ecs_service" "frontend" {
  name            = "frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = local.capacity_provider
    weight            = 1
  }

  network_configuration {
    subnets          = local.f.private_app_subnet_ids
    security_groups  = [local.sg.frontend]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 3000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  wait_for_steady_state = true

  depends_on = [
    aws_lb_listener.http,
    aws_route.private_app_to_nat,
    aws_ecs_cluster_capacity_providers.main,
    # Not a real dependency: waiting for RDS (~5-10 min) guarantees the NAT
    # instance has finished booting before the first image pull.
    aws_db_instance.main,
  ]
}
