# Incident Response Runbook: SecureStack

What I would actually do, step by step, if the detection layer built in this project fired. Written as a real runbook, not a theoretical one. Every tool and query named here exists in this AWS account right now.

## Scenario: GuardDuty finding fires

Example trigger: GuardDuty detects the EC2 instance communicating with an IP address on a known command-and-control list (finding type like `Backdoor:EC2/C&CActivity.B!DNS`).

### 1. Detect

No manual checking required, this is push-based. The moment GuardDuty generates a finding:
- EventBridge (`securestack-guardduty-findings` rule) matches it and fires two targets simultaneously.
- An email lands in the inbox subscribed to the `securestack-security-alerts` SNS topic. That's the trigger to start the process below.
- The same finding is written to the `/securestack/guardduty-findings` CloudWatch Log Group for investigation.

### 2. Triage: confirm what happened

Open CloudWatch → Logs Insights and run the saved query **"securestack / GuardDuty findings"** against `/securestack/guardduty-findings` to see the finding's severity, type, and title. Severity 7+ (High/Critical) means stop and treat this as active; severity <4 (Low) may be a false positive worth noting and moving on from.

Cross-reference with two more saved queries to build the full picture:
- **"securestack / Rejected network traffic"** (VPC Flow Logs): was this instance also generating rejected outbound connections around the same time? That would indicate it's actively trying to reach more destinations, not a one-off.
- **"securestack / IAM changes and root account usage"** (CloudTrail): did anything change in IAM around this time? A compromised instance's credentials being used to escalate privilege is the next thing an attacker would try.

The CloudWatch dashboard (`securestack-security-dashboard`) puts all of this on one screen instead of running each query manually.

### 3. Contain

The EC2 instance only has one role attached (`securestack-ec2-role`), scoped narrowly to SSM access and reading one specific SSM parameter (the DB password), not broad account access. That containment was designed in from the start, not bolted on after. Even a fully compromised instance can't pivot into IAM, S3, or other services.

Immediate containment steps:
1. **Isolate the instance.** Apply a security group that denies all inbound/outbound except SSM (SSM uses outbound HTTPS to AWS endpoints, so full network isolation isn't possible without also losing the ability to investigate the box; this is the standard tradeoff).
2. **Snapshot the EBS volume** before touching anything else, for forensics and rollback.
3. **Rotate the database password** in SSM Parameter Store immediately. That's the one credential the instance held, and it should be assumed compromised.
4. **Do not terminate the instance yet.** A live compromised instance is a source of evidence; terminating it destroys volatile data (running processes, network connections) that a snapshot alone won't fully capture.

### 4. Eradicate & recover

- Confirm via CloudTrail whether the attacker's activity is confined to this instance or touched anything else in the account (this is exactly what the IAM/root activity query is for).
- Once root cause is understood (compromised dependency, exposed credential, exploited app vulnerability), rebuild the instance from a known-good AMI rather than cleaning the existing one. Terraform makes this a `terraform taint aws_instance.app && terraform apply`, not a manual rebuild.
- Redeploy through the normal CI/CD pipeline so the fix goes through Checkov/Trivy scanning like any other change.

### 5. Post-incident

- Document what fired, what the triage queries showed, what containment steps were taken, root cause, and what changed afterward (new Config rule, tighter security group, dependency pin, etc.).
- If the root cause maps to a category Checkov could have caught, add a rule or tighten an existing exception in `SECURITY_EXCEPTIONS.md` rather than leaving it undocumented.

## Scenario: WAF blocks a malicious request (lower severity, no email alert by design)

WAF logs every request it evaluates, allowed and blocked, to the `aws-waf-logs-securestack` CloudWatch Log Group. This isn't wired to email alerting the way GuardDuty is, by design. WAF blocking a SQLi or Log4j attempt is the system working as intended, not an incident requiring a page. It's reviewed periodically (or live, in a demo) via CloudWatch Logs Insights to show the rule sets are actually intercepting real attack patterns, not just present in config.

## Why this design

A detection layer that only logs to a console nobody checks isn't meaningfully different from having no detection layer. The design choice throughout Phase 4 was that every finding needs a path to a human (email) and a path to investigation (searchable logs with pre-built queries), not just a checkbox that "monitoring exists."
