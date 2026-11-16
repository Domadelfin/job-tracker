output "app_url" {
  description = "Open this in a browser"
  value       = "http://${aws_lb.main.dns_name}"
}

output "db_endpoint" {
  description = "Private DNS name: resolves only inside the VPC"
  value       = aws_db_instance.main.address
}

output "db_secret_arn" {
  description = "Secrets Manager secret holding the DB username/password (managed by RDS)"
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "nat_public_ip" {
  description = "All outbound traffic from the private app subnets appears to come from this IP"
  value       = aws_instance.nat.public_ip
}

output "image_tag" {
  value = var.image_tag
}
