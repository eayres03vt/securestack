# ============================================================
# S3 bucket to store CloudTrail and Config logs. Private, encrypted,
# versioned so logs can't be silently overwritten - if an attacker
# ever tried to cover their tracks by deleting logs, versioning
# means the old versions are still recoverable.
# ============================================================
resource "aws_s3_bucket" "logs" {
  bucket = "${var.project_name}-logs-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-logs"
  }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Grants the CloudTrail and Config AWS services (not people) permission
# to write into this bucket - nothing else can.
resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.logs.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/cloudtrail/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Sid       = "AWSConfigWrite"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs.arn}/config/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Sid       = "AWSConfigBucketAcl"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.logs.arn
      }
    ]
  })
}

# ============================================================
# CloudTrail - records every API call made in this AWS account:
# who did it, when, from where, and what they did. This is the
# foundational audit log everything else builds on. If someone
# ever compromises this account, this is how you'd reconstruct
# exactly what they did.
# ============================================================
resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.logs.id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true # detects if log files are tampered with

  depends_on = [aws_s3_bucket_policy.logs]

  tags = {
    Name = "${var.project_name}-trail"
  }
}

# ============================================================
# GuardDuty - continuously analyzes CloudTrail logs, VPC network
# traffic, and DNS activity for signs of compromise (e.g. an
# instance talking to a known malware command-and-control server,
# unusual API calls, credential exfiltration patterns). This is
# the automated "threat detection" layer.
# ============================================================
resource "aws_guardduty_detector" "main" {
  enable = true
}

# ============================================================
# VPC Flow Logs - records metadata about network traffic in and
# out of the VPC (source, destination, port, whether it was
# accepted or rejected). Closes the Checkov finding (CKV2_AWS_11)
# we deferred to this phase.
# ============================================================
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/${var.project_name}/vpc-flow-logs"
  retention_in_days = 14 # keeps costs minimal while still useful for investigation

  tags = {
    Name = "${var.project_name}-flow-logs"
  }
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.project_name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "vpc-flow-logs.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.project_name}-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.flow_logs.arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id
}
