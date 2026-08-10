# Stores the database password in AWS's encrypted parameter store,
# using the same TF_VAR_db_password value you already set as an
# environment variable - no new secret to manage, and it never
# gets written into any file in the repo.
resource "aws_ssm_parameter" "db_password" {
  name  = "/${var.project_name}/db_password"
  type  = "SecureString"
  value = var.db_password

  tags = {
    Name = "${var.project_name}-db-password"
  }
}

# The KMS key AWS uses by default to encrypt SecureString parameters.
data "aws_kms_alias" "ssm" {
  name = "alias/aws/ssm"
}

# Extends the EC2 role from Phase 1 with permission to read ONLY this
# one parameter, and decrypt it with the SSM key - not all parameters,
# not any other secret. This is the same least-privilege principle as
# the SSM-instead-of-SSH decision earlier: give exactly what's needed,
# nothing more.
resource "aws_iam_role_policy" "read_db_password" {
  name = "${var.project_name}-read-db-password"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:GetParameter"
        Resource = aws_ssm_parameter.db_password.arn
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = data.aws_kms_alias.ssm.target_key_arn
      }
    ]
  })
}
