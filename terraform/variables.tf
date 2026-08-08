# Variables are inputs - values we can change without editing the actual
# resource definitions. Each has a default so `terraform apply` works out of
# the box, but any of these can be overridden later.

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix/tag all resources, so it's obvious what created them"
  type        = string
  default     = "securestack"
}

variable "vpc_cidr" {
  description = "IP address range for the whole VPC"
  type        = string
  default     = "10.0.0.0/16" # ~65,000 addresses - way more than we need, but it's the standard private range
}

# We spread subnets across two Availability Zones (AZs) - physically separate
# data centers within the region. If one AZ has an outage, resources in the
# other keep running. This is the basic idea behind "high availability."
variable "availability_zones" {
  description = "AZs to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (reachable from the internet)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (NOT reachable from the internet - database lives here)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type for the app server - free-tier eligible on newer AWS accounts"
  type        = string
  default     = "t3.micro"
}

variable "db_instance_class" {
  description = "RDS instance size - db.t3.micro is free-tier eligible"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Name of the database created inside RDS"
  type        = string
  default     = "securestack"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "dbadmin"
}

# No default on purpose - this forces you to supply it via an
# environment variable (TF_VAR_db_password) rather than it ending
# up written down anywhere in the repo. "sensitive = true" also
# tells Terraform to hide this value in plan/apply output.
variable "db_password" {
  description = "Master password for the database - set via TF_VAR_db_password env var, never in a file"
  type        = string
  sensitive   = true
}
