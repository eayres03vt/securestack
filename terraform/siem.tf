# ============================================================
# Lightweight SIEM layer - built on native AWS services instead of
# a dedicated tool like Wazuh. Wazuh's full stack needs ~4GB+ RAM
# to run reliably, which isn't free-tier eligible; this achieves
# the same core capabilities (alerting + searchable investigation
# queries) at effectively zero cost. See SECURITY_EXCEPTIONS.md for
# the full reasoning behind this tradeoff.
# ============================================================

# Real-time alerting - this is what makes it more than just logs
# sitting in a bucket. Subscribing your email means an actual
# notification lands in your inbox when GuardDuty finds something.
resource "aws_sns_topic" "security_alerts" {
  name = "${var.project_name}-security-alerts"
}

resource "aws_sns_topic_subscription" "security_alerts_email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = "eayres03vt@gmail.com"
}

# A CloudWatch Log Group to hold GuardDuty findings, so they're
# searchable with the same Logs Insights queries as everything else,
# not just visible one-at-a-time in the GuardDuty console.
resource "aws_cloudwatch_log_group" "guardduty_findings" {
  name              = "/${var.project_name}/guardduty-findings"
  retention_in_days = 90 # findings are worth keeping longer than routine logs

  tags = {
    Name = "${var.project_name}-guardduty-findings"
  }
}

# EventBridge rule that fires whenever GuardDuty generates a finding
# (of any severity). This is the "detection triggers a response"
# wiring - without this, GuardDuty would just quietly log findings
# that nobody ever looks at.
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "${var.project_name}-guardduty-findings"
  description = "Routes GuardDuty findings to email alerting and a searchable log group"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })
}

resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.security_alerts.arn
}

resource "aws_cloudwatch_event_target" "guardduty_to_logs" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "send-to-cloudwatch-logs"
  arn       = aws_cloudwatch_log_group.guardduty_findings.arn
}

# Permissions allowing EventBridge to actually publish to these
# two destinations - without this, the rule matches events but
# delivery silently fails.
resource "aws_sns_topic_policy" "security_alerts" {
  arn = aws_sns_topic.security_alerts.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgePublish"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.security_alerts.arn
      }
    ]
  })
}

resource "aws_cloudwatch_log_resource_policy" "eventbridge_to_logs" {
  policy_name = "${var.project_name}-eventbridge-to-logs"
  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgeToCloudWatchLogs"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource  = "${aws_cloudwatch_log_group.guardduty_findings.arn}:*"
      }
    ]
  })
}

# ============================================================
# Saved investigation queries - the "triage screen" of this
# lightweight SIEM. Anyone (you, in an interview demo, or a
# recruiter poking around) can open CloudWatch Logs Insights and
# run these directly instead of writing search queries from
# scratch, same idea as saved searches in a real SIEM.
# ============================================================
resource "aws_cloudwatch_query_definition" "failed_db_logins" {
  name = "${var.project_name} / Failed database login attempts"
  log_group_names = ["/aws/rds/instance/${var.project_name}-db/postgresql"]
  query_string = <<-EOT
    fields @timestamp, @message
    | filter @message like /FATAL/
    | sort @timestamp desc
    | limit 50
  EOT
}

resource "aws_cloudwatch_query_definition" "rejected_network_traffic" {
  name            = "${var.project_name} / Rejected network traffic (VPC Flow Logs)"
  log_group_names = [aws_cloudwatch_log_group.flow_logs.name]
  query_string = <<-EOT
    fields @timestamp, @message
    | filter @message like /REJECT/
    | sort @timestamp desc
    | limit 50
  EOT
}

resource "aws_cloudwatch_query_definition" "iam_and_root_activity" {
  name            = "${var.project_name} / IAM changes and root account usage"
  log_group_names = [aws_cloudwatch_log_group.cloudtrail.name]
  query_string = <<-EOT
    fields @timestamp, userIdentity.type, userIdentity.arn, eventName, sourceIPAddress
    | filter userIdentity.type = "Root" or eventSource = "iam.amazonaws.com"
    | sort @timestamp desc
    | limit 50
  EOT
}

resource "aws_cloudwatch_query_definition" "guardduty_findings_query" {
  name            = "${var.project_name} / GuardDuty findings"
  log_group_names = [aws_cloudwatch_log_group.guardduty_findings.name]
  query_string = <<-EOT
    fields @timestamp, detail.title, detail.severity, detail.type
    | sort @timestamp desc
    | limit 50
  EOT
}

# ============================================================
# Dashboard - the single screen that ties detection, network, and
# database visibility together. This is what you'd actually pull
# up to demo the monitoring layer.
# ============================================================
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-security-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "log",
        x      = 0, y = 0, width = 12, height = 6,
        properties = {
          title  = "Recent GuardDuty Findings"
          region = var.aws_region
          query  = "SOURCE '${aws_cloudwatch_log_group.guardduty_findings.name}' | fields @timestamp, detail.title, detail.severity | sort @timestamp desc | limit 20"
          view   = "table"
        }
      },
      {
        type   = "log",
        x      = 12, y = 0, width = 12, height = 6,
        properties = {
          title  = "Rejected Network Traffic"
          region = var.aws_region
          query  = "SOURCE '${aws_cloudwatch_log_group.flow_logs.name}' | filter @message like /REJECT/ | fields @timestamp, @message | sort @timestamp desc | limit 20"
          view   = "table"
        }
      },
      {
        type   = "log",
        x      = 0, y = 6, width = 12, height = 6,
        properties = {
          title  = "IAM & Root Account Activity"
          region = var.aws_region
          query  = "SOURCE '${aws_cloudwatch_log_group.cloudtrail.name}' | fields @timestamp, userIdentity.type, eventName | filter userIdentity.type = \"Root\" or eventSource = \"iam.amazonaws.com\" | sort @timestamp desc | limit 20"
          view   = "table"
        }
      },
      {
        type   = "log",
        x      = 12, y = 6, width = 12, height = 6,
        properties = {
          title  = "Failed Database Logins"
          region = var.aws_region
          query  = "SOURCE '/aws/rds/instance/${var.project_name}-db/postgresql' | filter @message like /FATAL/ | fields @timestamp, @message | sort @timestamp desc | limit 20"
          view   = "table"
        }
      }
    ]
  })
}
