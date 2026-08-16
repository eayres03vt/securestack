# Security Scan Exceptions

The CI/CD pipeline runs [Checkov](https://www.checkov.io/) against the Terraform code on every push, and blocks deployment if it fails. The checks below are intentionally excluded from that gate — not ignored, but reviewed and accepted, with reasoning documented here rather than silently suppressed. Anything not listed here is enforced.

## Cost tradeoffs (free-tier scope)

| Check | What it wants | Why it's excluded here |
|---|---|---|
| CKV_AWS_126 | EC2 detailed monitoring (1-min metrics) | ~$2/month per instance; basic 5-min monitoring (free) is sufficient for a portfolio-scale deployment |
| CKV_AWS_157 | RDS Multi-AZ | Roughly doubles RDS cost by running a live standby; not justified for a single-user demo environment |
| CKV_AWS_118 | RDS Enhanced Monitoring | Additional CloudWatch cost and complexity beyond what Performance Insights (already enabled) provides |
| CKV_AWS_337 | Customer-managed KMS key for SSM parameters | ~$1/month per key; the default AWS-managed key still provides encryption at rest, just without customer key rotation control |
| CKV_AWS_354 | Customer-managed KMS key for RDS Performance Insights | Same reasoning as above - the data is still encrypted by default, just with an AWS-managed key instead of a customer-managed one |
| CKV_AWS_158 | Customer-managed KMS key for CloudWatch Log Groups | Same reasoning - CloudWatch Logs are encrypted by default with an AWS-owned key regardless; a customer-managed key adds ~$1/month for key rotation control we don't need at this scale |
| CKV_AWS_35 | Customer-managed KMS key for CloudTrail logs | Same reasoning - the S3 bucket storing CloudTrail logs is already encrypted (AES256); a dedicated CMK is an incremental cost for a control that's largely redundant here |
| CKV_AWS_144 | S3 cross-region replication for the logs bucket | Adds storage cost in a second region plus replication overhead; not justified for a single-account portfolio project with no regional-failure requirement |

## Intentional design decisions

| Check | What it wants | Why it's excluded here |
|---|---|---|
| CKV_AWS_260 | No security group should allow port 80 from 0.0.0.0/0 | This is a public web application by design — the entire point is HTTP access from anywhere. Mitigated by: no SSH exposure, database isolated in a private subnet, WAF planned for Phase 4 |
| CKV_AWS_382 (x2) | No security group should allow all outbound traffic | Both the app and database security groups need outbound access (app: DB connections, AWS API calls for SSM/Parameter Store; db: OS/engine updates). Narrowing this further didn't provide meaningful risk reduction given inbound is already tightly scoped |
| CKV_AWS_130 (x2) | Subnets should not auto-assign public IPs | Public subnets are specifically the tier meant to be internet-reachable in this two-tier architecture; this is the intended behavior, not an oversight |
| CKV_AWS_293 | RDS deletion protection | Intentionally disabled so `terraform destroy` can fully tear down the environment during development to control cost between work sessions. Would be enabled in a real production deployment |
| CKV_AWS_18 | S3 server access logging on the logs bucket | Would require a second, separate S3 bucket purely to hold access logs (AWS best practice against logging a bucket to itself). CloudTrail already provides account-level audit logging of S3 API calls; a dedicated access-log bucket for this one low-traffic bucket wasn't judged worth the added infrastructure |
| CKV2_AWS_62 | S3 event notifications on the logs bucket | Would require an SNS/SQS destination with no current consumer - deferred until there's an actual automation that needs to react to new log objects landing in the bucket |
| CKV2_AWS_3 | GuardDuty enabled account/organization-wide via AWS Organizations | This project uses a single standalone AWS account with no AWS Organizations setup; this check is oriented at multi-account environments and doesn't apply here. GuardDuty is enabled and active on the account regardless |
| CKV_AWS_338 | CloudWatch Log Group retention of at least 1 year | Retention is set to 14 days instead. The RDS parameter group logs every query (`log_statement=all`) to satisfy CKV2_AWS_30, which generates meaningful log volume; a full year of retention at that verbosity would add non-trivial storage cost for a portfolio project. 14 days is enough to demonstrate the logging pipeline works and support near-term investigation |

## Fixed (not excluded)

Everything else Checkov originally flagged was fixed directly in the Terraform code: EBS encryption, EBS optimization, IMDSv2 enforcement, security group rule descriptions, RDS auto minor-version upgrades, RDS Performance Insights, RDS IAM authentication support, RDS CloudWatch log export, locking down the VPC's default security group, VPC Flow Logs (CKV2_AWS_11, added in Phase 4 alongside CloudTrail/GuardDuty), and RDS query logging via a custom parameter group (CKV2_AWS_30, added in Phase 4).
