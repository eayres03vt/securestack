# Looks up the latest Amazon Linux 2023 image AWS publishes, so we
# don't have to hardcode an AMI ID that goes stale over time.
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# ============================================================
# The actual server. Sits in the first public subnet, uses the
# app security group (port 80 in, no SSH), and is attached to the
# IAM role above so Session Manager can reach it.
#
# t2.micro is free-tier eligible: 750 hours/month free for the
# first 12 months on a new account - enough to run this 24/7 at
# no cost.
# ============================================================
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  ebs_optimized          = true

  # Requires IMDSv2 (a hardened version of the metadata service that's
  # resistant to SSRF-based credential theft) instead of allowing the
  # older, less secure IMDSv1. Free, no reason not to.
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  # Encrypts the server's root disk at rest. Free, no performance cost.
  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "${var.project_name}-app-server"
  }
}
