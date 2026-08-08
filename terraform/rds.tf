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
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az                = false

  backup_retention_period = 1
  skip_final_snapshot     = true

  tags = {
    Name = "${var.project_name}-db"
  }
}
