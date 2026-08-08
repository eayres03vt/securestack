# ============================================================
# App security group - firewall rules for the web server.
# Allows inbound HTTP from anywhere (it's a public web app),
# and allows all outbound traffic (needed to reach the database,
# download updates, talk to AWS APIs for Session Manager, etc).
#
# Notice there's no port 22 (SSH) opened here. SSH is one of the
# most commonly attacked ports on the internet. Instead, we'll
# use AWS Systems Manager Session Manager for shell access, which
# works through AWS's API rather than an open network port - no
# SSH key to manage or leak.
# ============================================================
resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Allow HTTP inbound, all outbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-app-sg"
  }
}

# ============================================================
# Database security group - the important one for the "private
# subnet" concept to actually mean something. It only accepts
# inbound traffic from the app security group specifically -
# not from any IP address, not even yours. The only way to reach
# the database at all is by being the app server.
# ============================================================
resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Allow Postgres only from the app security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from app servers only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}
