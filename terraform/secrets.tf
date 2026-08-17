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
        Resource = [
          aws_ssm_parameter.db_password.arn,
          aws_ssm_parameter.flask_secret_key.arn,
          aws_ssm_parameter.admin_password.arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = data.aws_kms_alias.ssm.target_key_arn
      }
    ]
  })
}

# ============================================================
# Flask's SECRET_KEY signs session cookies and (as of this round of
# fixes) CSRF tokens - if it's predictable or hardcoded, anyone can
# forge both. The app previously fell back to a hardcoded literal
# string ("dev-only-not-for-production") that was never actually
# overridden in production, meaning the real deployment was signing
# cookies with a value sitting in plain text in a public GitHub repo.
# Fixed the same way the DB password is handled: generate a real
# random value, store it encrypted in SSM, fetch it at runtime via
# the instance's IAM role - never written to disk or committed.
# ============================================================
resource "random_password" "flask_secret_key" {
  length  = 50
  special = true
}

resource "aws_ssm_parameter" "flask_secret_key" {
  name  = "/${var.project_name}/flask_secret_key"
  type  = "SecureString"
  value = random_password.flask_secret_key.result

  tags = {
    Name = "${var.project_name}-flask-secret-key"
  }
}

# ============================================================
# App login - answers the "anyone with the URL can add/edit/delete
# items" finding without needing HTTPS/a domain (unlike the Cognito
# approach originally tried here, which Cognito itself rejected: it
# refuses to redirect a login to a plain-HTTP address). This is a
# single admin account, generated randomly and stored encrypted in
# SSM - same trust model as the DB password - checked with a
# constant-time comparison in the app instead of Flask managing its
# own user database for what's a single-user internal tool.
# ============================================================
resource "random_password" "admin_password" {
  length  = 20
  special = true
}

resource "aws_ssm_parameter" "admin_password" {
  name  = "/${var.project_name}/admin_password"
  type  = "SecureString"
  value = random_password.admin_password.result

  tags = {
    Name = "${var.project_name}-admin-password"
  }
}
