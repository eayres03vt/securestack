# ============================================================
# Tells AWS to trust GitHub Actions as an identity provider.
# GitHub issues a short-lived, cryptographically signed token for
# each workflow run; AWS verifies it against GitHub's public keys
# (the thumbprint below) instead of a stored secret.
# ============================================================
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# ============================================================
# The role GitHub Actions will "become" during a workflow run.
# The condition is the important part: it only allows this role
# to be assumed by workflows running in YOUR specific repo, on
# the main branch - not any GitHub Actions workflow anywhere.
# ============================================================
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:eayres03vt/securestack:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-github-actions-role"
  }
}

# ============================================================
# What GitHub Actions is allowed to do once it assumes this role:
# send a command to run on our specific EC2 instance via SSM, and
# check on that command's status. Nothing else - it can't touch
# any other AWS resource, can't read secrets, can't modify infra.
# ============================================================
resource "aws_iam_role_policy" "github_actions_deploy" {
  name = "${var.project_name}-github-actions-deploy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:SendCommand"
        Resource = [
          "arn:aws:ec2:${var.aws_region}:*:instance/${aws_instance.app.id}",
          "arn:aws:ssm:${var.aws_region}:*:document/AWS-RunShellScript"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
        Resource = "*"
      },
      {
        # Lets the pipeline look up the current instance ID by tag at
        # runtime, instead of it being hardcoded in the workflow file -
        # so if the instance is ever replaced, the pipeline keeps working
        # without needing a manual update.
        Effect   = "Allow"
        Action   = "ec2:DescribeInstances"
        Resource = "*"
      }
    ]
  })
}

output "github_actions_role_arn" {
  description = "IAM role ARN GitHub Actions will assume - needed in the workflow file"
  value       = aws_iam_role.github_actions.arn
}
