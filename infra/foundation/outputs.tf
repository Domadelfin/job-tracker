# Read by the runtime layer via terraform_remote_state.

output "region" { value = var.region }
output "project" { value = var.project }

output "vpc_id" { value = aws_vpc.main.id }
output "vpc_cidr" { value = aws_vpc.main.cidr_block }

output "public_subnet_ids" { value = aws_subnet.public[*].id }
output "private_app_subnet_ids" { value = aws_subnet.private_app[*].id }
output "private_db_subnet_ids" { value = aws_subnet.private_db[*].id }

output "private_app_route_table_id" { value = aws_route_table.private_app.id }

output "security_group_ids" {
  value = {
    alb      = aws_security_group.alb.id
    frontend = aws_security_group.frontend.id
    backend  = aws_security_group.backend.id
    db       = aws_security_group.db.id
    nat      = aws_security_group.nat.id
  }
}
