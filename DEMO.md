# Demo & Teardown

## What actually costs money here

Everything in this project runs inside AWS free tier except AWS WAF (~$8-10/month, no free tier). That's the only "subscription" in the normal sense: it accrues automatically every month until it's destroyed. Everything else (VPC, EC2, RDS, ALB, CloudTrail, GuardDuty, Config, the SIEM layer) has no ongoing cost at this scale, so there's nothing else to cancel on a recurring basis.

## Demoing the project

The live app URL, CI/CD pipeline, security dashboard, and WAF are all deployed and ready to walk through at any time; nothing needs to be turned on first. A full demo would typically cover:

1. The architecture (README.md, the Mermaid diagram)
2. The live app, logging in and using it
3. A CI/CD pipeline run (push a small change, watch Checkov/Trivy scan it, then deploy)
4. The CloudWatch security dashboard
5. WAF actually blocking a malicious-looking request (e.g. a basic SQL injection attempt in a URL parameter)

## When you're done demoing (removes the one paid resource)

This tears down just WAF. Everything else, including the app, database, load balancer, and monitoring, keeps running normally, and the app URL doesn't change:

```bash
cd terraform
export TF_VAR_db_password='SecureStack2026x'
terraform destroy -target=aws_wafv2_web_acl_association.main -target=aws_wafv2_web_acl.main
```

## When you're completely done with the project (removes everything)

This stops all AWS spend from this project entirely, including the free-tier resources (they're free, but AWS free tier still has limits, and it's good practice to not leave infrastructure running indefinitely once it's no longer needed):

```bash
cd terraform
export TF_VAR_db_password='SecureStack2026x'
terraform destroy
```

This deletes the VPC, EC2 instance, RDS database, load balancer, CloudTrail trail, GuardDuty detector, and everything else Terraform created. The app URL stops working after this. Keep the repo and its documentation (README, SECURITY_EXCEPTIONS.md, IR-RUNBOOK.md) as the portfolio artifact; the infrastructure itself doesn't need to keep running for the project to be worth showing.
