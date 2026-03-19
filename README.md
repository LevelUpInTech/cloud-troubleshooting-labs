# Level Up in Tech — Cloud Troubleshooting Simulation Labs

**Hands-on AWS troubleshooting labs with intentionally broken Terraform infrastructure.**

Each lab deploys real AWS infrastructure using Terraform that contains hidden bugs. Your job is to deploy the infrastructure, identify what's broken, and fix it — just like you would on the job.

---

## Labs Included

### Lab 01: Cloud Engineer — Multi-AZ Architecture Failure
**Scenario:** A healthcare SaaS app's "high availability" architecture goes completely offline during an AZ outage. No failover happened. Find 5 architectural flaws and fix them.

**What gets deployed:** VPC, ALB, Auto Scaling Group, RDS MySQL, NAT Gateway

**Skills tested:** VPC networking, multi-AZ design, RDS failover, CloudWatch monitoring

### Lab 02: Cloud DevOps Engineer — Broken CI/CD Pipeline
**Scenario:** A CI/CD pipeline deployed broken code directly to production with zero testing. 30% of users see 502 errors. Roll back, then harden the pipeline.

**What gets deployed:** ECS Fargate, ECR, CodePipeline, CodeBuild, ALB

**Skills tested:** CI/CD pipeline design, ECS troubleshooting, deployment strategies, rollback procedures

### Lab 03: AI/ML Engineer — Production SageMaker Failure
**Scenario:** A fraud detection model is missing 40% of fraud and the endpoint crashes under load. Diagnose data drift, fix the endpoint, retrain, and add monitoring.

**What gets deployed:** S3 buckets, SageMaker model/endpoint, IAM roles

**Skills tested:** SageMaker operations, data drift detection, model retraining, ML monitoring

---

## Quick Start

```bash
# Clone this repository
git clone https://github.com/LevelUpInTech/cloud-troubleshooting-labs.git
cd cloud-troubleshooting-labs

# Pick a lab
cd 01-cloud-engineer-multi-az

# Configure variables
cp terraform.tfvars.example terraform.tfvars

# Deploy the broken infrastructure
terraform init
terraform apply

# IMPORTANT: Destroy when done to avoid charges
terraform destroy
```

## How Each Lab Works

1. **Deploy** — Run terraform apply to spin up the intentionally broken infrastructure
2. **Investigate** — Use the AWS Console and CLI to find what's wrong
3. **Fix** — Modify the Terraform code to fix the bugs
4. **Apply** — Run terraform apply again to deploy your fixes
5. **Verify** — Confirm everything works correctly
6. **Destroy** — Run terraform destroy when done

## Answer Keys

Each main.tf file has an answer key at the bottom (clearly marked). Try to find the bugs yourself first!

---

**Level Up in Tech** — Building the Next Generation of Cloud Engineers
