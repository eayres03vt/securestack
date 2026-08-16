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

## Intentional design decisions

| Check | What it wants | Why it's excluded here |
|---|---|---|
| CKV_AWS_260 | No security group should allow port 80 from 0.0.0.0/0 | This is a public web application by design — the entire point is HTTP access from anywhere. Mitigated by: no SSH exposure, database isolated in a private subnet, WAF planned for Phase 4 |
| CKV_AWS_382 (x2) | No security group should allow all outbound traffic | Both the app and database security groups need outbound access (app: DB connections, AWS API calls for SSM/Parameter Store; db: OS/engine updates). Narrowing this further didn't provide meaningful risk reduction given inbound is already tightly scoped |
| CKV_AWS_130 (x2) | Subnets should not auto-assign public IPs | Public subnets are specifically the tier meant to be internet-reachable in this two-tier architecture; this is the intended behavior, not an oversight |
| CKV_AWS_293 | RDS deletion protection | Intentionally disabled so `terraform destroy` can fully tear down the environment during development to control cost between work sessions. Would be enabled in a real production deployment |

## Fixed (not excluded)

Everything else Checkov originally flagged was fixed directly in the Terraform code: EBS encryption, EBS optimization, IMDSv2 enforcement, security group rule descriptions, RDS auto minor-version upgrades, RDS Performance Insights, RDS IAM authentication support, RDS CloudWatch log export, locking down the VPC's default security group, VPC Flow Logs (CKV2_AWS_11, added in Phase 4 alongside CloudTrail/GuardDuty), and RDS query logging via a custom parameter group (CKV2_AWS_30, added in Phase 4).
