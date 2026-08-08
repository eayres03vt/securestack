# ============================================================
# IAM role for the EC2 instance. This is what lets the server
# itself act as an identity in AWS - specifically, so AWS Systems
# Manager can connect to it for shell access without SSH.
#
# "assume_role_policy" says: only the EC2 service is allowed to
# use this role (a database or a person can't accidentally pick
# it up).
# ============================================================
resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ec2-role"
  }
}

# AWS-managed policy that grants exactly what Session Manager
# needs - nothing more. This is the "least privilege" principle
# in practice: we're attaching a narrow, purpose-built policy
# instead of something broad like AdministratorAccess.
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# An instance profile is just the wrapper that lets an EC2
# instance actually use an IAM role - roles can't be attached
# to instances directly, only through this.
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2.name
}
