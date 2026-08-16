# Custom parameter group enabling query logging - closes the Checkov
# finding (CKV2_AWS_30) we deferred earlier. Logs get shipped to
# CloudWatch via enabled_cloudwatch_logs_exports on the DB instance
# below, giving visibility into what queries actually ran.
resource "aws_db_parameter_group" "main" {
  name   = "${var.project_name}-postgres-params"
  family = "postgres16"

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1"
  }

  tags = {
    Name = "${var.project_name}-postgres-params"
  }
}

# RDS instances need to know which subnets they're allowed to live
# in. We point this at the private subnets only - the database
# will never get a public IP or a route to the internet.
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# ============================================================
# The actual database. A few choices worth explaining:
#  - publicly_accessible = false: no public IP, ever. Combined
#    with the private subnet, this database is unreachable from
#    the internet no matter what.
#  - storage_encrypted = true: data at rest is encrypted, free to
#    enable, no reason not to.
#  - skip_final_snapshot = true: normally AWS takes a backup
#    snapshot before deleting a database (good in production).
#    We skip it here so `terraform destroy` works cleanly for a
#    learning project without leaving orphaned snapshots around.
#  - db.t3.micro / 20GB: stays within free tier limits.
# ============================================================
resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type       = "gp2"
  storage_encrypted  = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az                = false

  backup_retention_period = 1
  skip_final_snapshot     = true

  # All free, zero-tradeoff hardening:
  auto_minor_version_upgrade     = true # picks up security patches automatically
  copy_tags_to_snapshot          = true
  performance_insights_enabled   = true # free for 7-day retention on this instance class
  iam_database_authentication_enabled = true # makes IAM-based DB auth available as an option
  enabled_cloudwatch_logs_exports = ["postgresql"] # ships DB logs to CloudWatch

  tags = {
    Name = "${var.project_name}-db"
  }
}
