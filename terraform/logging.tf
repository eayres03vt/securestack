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

# Automatically moves old logs to cheaper storage, then deletes them
# after a year - keeps a full year of audit history available (useful
# for any investigation) without the bucket growing and costing more
# indefinitely.
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "archive-and-expire"
    status = "Enabled"

    filter {} # applies to every object in the bucket

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 365
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

# SNS topic CloudTrail notifies whenever a new log file is delivered.
# Also gives us a ready-made hook to wire up email alerts on later
# (e.g. GuardDuty findings) without adding new infrastructure then.
resource "aws_sns_topic" "cloudtrail" {
  name = "${var.project_name}-cloudtrail-notifications"
}

resource "aws_sns_topic_policy" "cloudtrail" {
  arn = aws_sns_topic.cloudtrail.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailSNSPolicy"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.cloudtrail.arn
      }
    ]
  })
}

# CloudTrail's primary copy goes to S3 (long-term, tamper-evident
# archive). This second destination - CloudWatch Logs - is what makes
# it actually queryable/searchable in near-real-time, which is the
# foundation of the lightweight "SIEM" layer below.
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/${var.project_name}/cloudtrail"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-cloudtrail-logs"
  }
}

resource "aws_iam_role" "cloudtrail_to_cloudwatch" {
  name = "${var.project_name}-cloudtrail-cwl-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "cloudtrail_to_cloudwatch" {
  name = "${var.project_name}-cloudtrail-cwl-policy"
  role = aws_iam_role.cloudtrail_to_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
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
  sns_topic_name                = aws_sns_topic.cloudtrail.name

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_to_cloudwatch.arn

  depends_on = [aws_s3_bucket_policy.logs, aws_sns_topic_policy.cloudtrail]

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
