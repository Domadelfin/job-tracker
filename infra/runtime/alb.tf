# ---------------------------------------------------------------------------
# Application Load Balancer: the only public entry point.
#   /api, /api/*  -> backend target group  (Node API, port 4000)
#   everything else -> frontend target group (Next.js, port 3000)
# HTTP only: HTTPS needs a domain + ACM certificate (free) + a 443 listener.
# ---------------------------------------------------------------------------

resource "aws_lb" "main" {
  name               = "${local.project}-alb"
  load_balancer_type = "application"
  internal           = false
  subnets            = local.f.public_subnet_ids
  security_groups    = [local.sg.alb]

  drop_invalid_header_fields = true # mitigates HTTP request smuggling
}

resource "aws_lb_target_group" "frontend" {
  name                 = "${local.project}-frontend"
  port                 = 3000
  protocol             = "HTTP"
  vpc_id               = local.f.vpc_id
  target_type          = "ip" # required for Fargate (awsvpc networking)
  deregistration_delay = 15   # default 300s would make deploys/destroys crawl

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }
}

resource "aws_lb_target_group" "backend" {
  name                 = "${local.project}-backend"
  port                 = 4000
  protocol             = "HTTP"
  vpc_id               = local.f.vpc_id
  target_type          = "ip"
  deregistration_delay = 15

  health_check {
    path                = "/api/health" # liveness only: doesn't touch the DB
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  condition {
    path_pattern {
      values = ["/api", "/api/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}
