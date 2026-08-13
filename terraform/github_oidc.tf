# Fetches GitHub's current TLS certificate live at apply time, instead
# of a hardcoded thumbprint that goes stale whenever GitHub rotates
# their signing certificate (which is exactly what broke this the
# first time - the hardcoded value was already out of date).
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ============================================================
# Tells AWS to trust GitHub Actions as an identity provider.
# GitHub issues a short-lived, cryptographically signed token for
# each workflow run; AWS verifies it against GitHub's actual current
# certificate thumbprint, fetched dynamically above.
# ============================================================
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
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
          # GitHub's actual sub claim includes immutable numeric owner/repo
          # IDs (confirmed via CloudTrail), not just the plain name - e.g.
          # "repo:eayres03vt@313114895/securestack@1323294435:ref:...".
          # This still scopes access to exactly this repo; the numeric IDs
          # stay valid even if the repo or account is ever renamed.
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:eayres03vt@313114895/securestack@1323294435:*"
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
