# ---------------------------------------------------------------------------
# Security groups (free). Each is a stateful firewall around one component.
# Rules reference other security groups instead of IP ranges where possible,
# so "only the ALB can reach the frontend" stays true even as IPs change.
#
#   Internet --80--> ALB --3000--> frontend
#                        --4000--> backend --5432--> database
#   frontend/backend --443--> NAT instance --> internet (ECR, Secrets Manager, CloudWatch Logs)
#
# Note: Terraform removes AWS's default "allow all outbound" rule from groups it
# creates, so every group below can only send the traffic explicitly listed.
# ---------------------------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "${var.project}-alb"
  description = "Public load balancer"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project}-alb" }
}

resource "aws_security_group" "frontend" {
  name        = "${var.project}-frontend"
  description = "Next.js ECS tasks"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project}-frontend" }
}

resource "aws_security_group" "backend" {
  name        = "${var.project}-backend"
  description = "Node API ECS tasks"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project}-backend" }
}

resource "aws_security_group" "db" {
  name        = "${var.project}-db"
  description = "RDS PostgreSQL - reachable only from the backend"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project}-db" }
}

resource "aws_security_group" "nat" {
  name        = "${var.project}-nat"
  description = "NAT instance - forwards outbound traffic from private app subnets"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.project}-nat" }
}

# --- ALB -------------------------------------------------------------------
# HTTP only: HTTPS needs a TLS certificate, which needs a domain name you own.
# If you buy a domain later, add a 443 listener with a free ACM certificate.

resource "aws_vpc_security_group_ingress_rule" "alb_http_from_internet" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_frontend" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to frontend tasks"
  referenced_security_group_id = aws_security_group.frontend.id
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
}

resource "aws_vpc_security_group_egress_rule" "alb_to_backend" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward to backend tasks"
  referenced_security_group_id = aws_security_group.backend.id
  ip_protocol                  = "tcp"
  from_port                    = 4000
  to_port                      = 4000
}

# --- Frontend --------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "frontend_from_alb" {
  security_group_id            = aws_security_group.frontend.id
  description                  = "Only the ALB can reach the frontend"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
}

resource "aws_vpc_security_group_egress_rule" "frontend_https_out" {
  security_group_id = aws_security_group.frontend.id
  description       = "HTTPS to AWS APIs (ECR image pulls, CloudWatch Logs) via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# --- Backend ---------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "backend_from_alb" {
  security_group_id            = aws_security_group.backend.id
  description                  = "Only the ALB can reach the API"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 4000
  to_port                      = 4000
}

resource "aws_vpc_security_group_egress_rule" "backend_to_db" {
  security_group_id            = aws_security_group.backend.id
  description                  = "PostgreSQL to RDS"
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_egress_rule" "backend_https_out" {
  security_group_id = aws_security_group.backend.id
  description       = "HTTPS to AWS APIs (ECR, Secrets Manager, CloudWatch Logs) via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# --- Database: one inbound rule, no outbound rules -------------------------

resource "aws_vpc_security_group_ingress_rule" "db_from_backend" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from backend tasks only"
  referenced_security_group_id = aws_security_group.backend.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# --- NAT instance ----------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "nat_from_private_app" {
  for_each = { for i, s in aws_subnet.private_app : s.availability_zone => s.cidr_block }

  security_group_id = aws_security_group.nat.id
  description       = "HTTPS from private app subnet ${each.key}"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "nat_https_out" {
  security_group_id = aws_security_group.nat.id
  description       = "Forward HTTPS to the internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "nat_http_out" {
  security_group_id = aws_security_group.nat.id
  description       = "HTTP for OS package repositories during NAT instance boot"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}
