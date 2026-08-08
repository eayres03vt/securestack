# SecureStack — Project Plan

**Goal:** A cloud-native, security-hardened inventory management app, built to demonstrate both IT/cloud engineering and cybersecurity skills for job applications. Rebuilds the concept of the Richmond SharePoint inventory system as a production-style AWS deployment.

**Who this is for:** IT engineering and software/security roles. The story you'll tell in interviews: "I took a real system I built at work and re-engineered it as a secure, automated, cloud-native system — here's the architecture, here's how I hardened and monitored it."

---

## How we're working

You review and approve each step — nothing gets deployed to your AWS account without you understanding what it does and why. I'll explain concepts as we go (this doubles as Network+ / cloud study material). You keep AWS credentials; I never need them.

---

## Phase 0 — Accounts (you, in progress)
- GitHub account + `securestack` repo
- AWS free tier account, root MFA enabled, IAM admin user created

## Phase 1 — Infrastructure as Code (Terraform)
Build the AWS foundation: VPC with public/private subnets, security groups, IAM roles (least privilege), an EC2 instance or ECS service for the app, RDS (or DynamoDB) for data.
**You'll learn:** networking fundamentals (subnets, routing, NACLs vs security groups), IAM policy design, why IaC matters over clicking around the console.

## Phase 2 — The App
Small full-stack inventory management app (items, locations, check-in/check-out) — Python/Flask or Node, simple frontend, deployed onto the Phase 1 infra.
**You'll learn:** how app deployment connects to infra, environment config, secrets handling.

## Phase 3 — CI/CD Pipeline
GitHub Actions: on push, run tests, run security scans (Checkov for Terraform misconfig, Trivy for container/dependency vulnerabilities), then deploy.
**You'll learn:** DevSecOps basics — shifting security left instead of bolting it on after.

## Phase 4 — Security Monitoring & Detection
- CloudTrail (who did what, when)
- GuardDuty (threat detection)
- AWS Config (config drift / compliance rules)
- WAF in front of the app
- Centralized logging into a lightweight SIEM (Wazuh), so you can demo actual alert triage
**You'll learn:** the detection side of security — this is the part most "cloud projects" skip, and it's what makes this one stand out.

## Phase 5 — Documentation & Portfolio Polish
- Architecture diagram
- Incident response runbook (what you'd do if GuardDuty fired an alert)
- README written as a case study (problem → design decisions → tradeoffs → what you'd do differently at scale)

---

## Target Timeline (goal: finished by end of August 2026)
- Week 1 (Aug 4–10): Phase 1 — Terraform infra
- Week 2 (Aug 11–17): Phase 2 — App build
- Week 3 (Aug 18–24): Phase 3 — CI/CD, start Phase 4 monitoring/SIEM
- Week 4 (Aug 25–31): Finish Phase 4, Phase 5 docs/diagram/runbook, polish
- Suggested daily split: mornings on the project, afternoons on job applications/networking, so there's something to show recruiters throughout rather than only at the end.

## Cost note
Everything is scoped to stay within AWS free tier limits. I'll flag any resource before we create it if it risks a charge, and we'll tear down anything left running when you're not actively demoing it.

## Status
- [ ] Phase 0 — Accounts
- [ ] Phase 1 — IaC
- [ ] Phase 2 — App
- [ ] Phase 3 — CI/CD
- [ ] Phase 4 — Monitoring
- [ ] Phase 5 — Docs
