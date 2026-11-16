# ---------------------------------------------------------------------------
# VPC: three subnet tiers across two Availability Zones (all free resources)
#
#   public       10.0.0.0/24,  10.0.1.0/24   -> Internet Gateway   (ALB, NAT instance)
#   private-app  10.0.10.0/24, 10.0.11.0/24  -> NAT (outbound only, route added by runtime layer)
#   private-db   10.0.20.0/24, 10.0.21.0/24  -> no internet route at all (RDS)
# ---------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # required for RDS endpoints and AWS service hostnames
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" }
}

# Lock down the VPC's default security group: no rules at all, so nothing can
# accidentally rely on it. (Security best practice / CIS benchmark.)
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-default-DO-NOT-USE" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

# --- Subnets ---------------------------------------------------------------

resource "aws_subnet" "public" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index) # 10.0.0.0/24, 10.0.1.0/24

  # Don't hand out public IPs automatically; anything public must opt in.
  map_public_ip_on_launch = false

  tags = { Name = "${var.project}-public-${local.azs[count.index]}", Tier = "public" }
}

resource "aws_subnet" "private_app" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 10 + count.index) # 10.0.10.0/24, 10.0.11.0/24

  tags = { Name = "${var.project}-private-app-${local.azs[count.index]}", Tier = "private-app" }
}

resource "aws_subnet" "private_db" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.main.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 20 + count.index) # 10.0.20.0/24, 10.0.21.0/24

  tags = { Name = "${var.project}-private-db-${local.azs[count.index]}", Tier = "private-db" }
}

# --- Route tables ----------------------------------------------------------
# A subnet is "public" only because its route table sends 0.0.0.0/0 to the IGW.

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private app: only the implicit "local" (inside-VPC) route here. The runtime
# layer adds 0.0.0.0/0 -> NAT instance while it exists, and removes it on destroy.
resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-private-app-rt" }
}

resource "aws_route_table_association" "private_app" {
  count          = length(aws_subnet.private_app)
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app.id
}

# Private DB: local route only, permanently. The database has no path to or
# from the internet even if a security group were misconfigured.
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-private-db-rt" }
}

resource "aws_route_table_association" "private_db" {
  count          = length(aws_subnet.private_db)
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}

# --- S3 gateway endpoint (free) --------------------------------------------
# ECR stores image layers in S3. This lets Fargate download them over AWS's
# network instead of through the NAT: faster, and no NAT bandwidth.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_app.id]

  tags = { Name = "${var.project}-s3-gateway" }
}
