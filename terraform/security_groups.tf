# ============================================================
# Load balancer security group - this is now the only thing
# actually exposed to the whole internet on port 80.
# ============================================================
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP inbound from anywhere, forwards to the app server"
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
    Name = "${var.project_name}-alb-sg"
  }
}

# ============================================================
# App security group - firewall rules for the web server.
# Now only accepts traffic from the load balancer's security
# group, not from the internet directly - the EC2 instance is no
# longer reachable except through the load balancer, even though
# it technically still has a public IP for Session Manager to use.
#
# Notice there's no port 22 (SSH) opened here. SSH is one of the
# most commonly attacked ports on the internet. Instead, we use
# AWS Systems Manager Session Manager for shell access, which
# works through AWS's API rather than an open network port - no
# SSH key to manage or leak.
# ============================================================
resource "aws_security_group" "app" {
  # name_prefix instead of a fixed name - required for
  # create_before_destroy below, since AWS won't allow two security
  # groups with the identical exact name to exist at the same time
  # even briefly during a replacement.
  name_prefix = "${var.project_name}-app-sg-"
  description = "Allow HTTP only from the load balancer, all outbound"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from the load balancer only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
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

  # Create the replacement security group (and let dependent resources
  # like the DB security group and EC2 instance update to reference it)
  # BEFORE deleting the old one - this is exactly what fixed the
  # DependencyViolation error: the old SG can only be deleted once
  # nothing points at it anymore.
  lifecycle {
    create_before_destroy = true
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
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}
