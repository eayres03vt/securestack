# Outputs print useful values after `terraform apply` finishes, and let other
# Terraform configs (like Phase 2's app resources) reference these without
# hardcoding IDs.

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "app_server_public_ip" {
  description = "Public IP of the EC2 app server - use this to view the app in a browser"
  value       = aws_instance.app.public_ip
}

output "app_server_instance_id" {
  description = "Instance ID - needed to start an SSM session"
  value       = aws_instance.app.id
}

output "db_endpoint" {
  description = "RDS connection endpoint (host:port)"
  value       = aws_db_instance.main.endpoint
}
