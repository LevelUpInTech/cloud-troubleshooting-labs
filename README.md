# Level Up in Tech — Cloud Troubleshooting Simulation Labs

**Hands-on AWS troubleshooting labs with intentionally broken infrastructure.**

Each lab deploys real AWS infrastructure using Terraform that contains hidden bugs. Your job is to deploy the infrastructure, identify what's broken, and fix it — just like you would on the job.

---

## Labs Included

### Lab 01: Cloud Engineer — Multi-AZ Architecture Failure
**Scenario:** A healthcare SaaS app's "high availability" architecture goes completely offline during an AZ outage. No failover happened. Find 5 architectural flaws and fix them.

**What gets deployed:** VPC, ALB, Auto Scaling Group, RDS MySQL, NAT Gateway

**Skills tested:** VPC networking, multi-AZ design, RDS failover, CloudWatch monitoring

**Estimated cost:** ~$2-3/day (mostly RDS)

### Lab 02: Cloud DevOps Engineer — Broken CI/CD Pipeline
**Scenario:** A CI/CD pipeline deployed broken code directly to production with zero testing. 30% of users see 502 errors. Roll back, then harden the pipeline.

**What gets deployed:** ECS Fargate, ECR, CodePipeline, CodeBuild, ALB

**Skills tested:** CI/CD pipeline design, ECS troubleshooting, deployment strategies, rollback procedures

**Estimated cost:** ~$1-2/day (mostly ALB + Fargate)

### Lab 03: AI/ML Engineer — Production SageMaker Failure
**Scenario:** A fraud detection model is missing 40% of fraud and the endpoint crashes under load. Diagnose data drift, fix the endpoint, retrain, and add monitoring.

**What gets deployed:** S3 buckets, SageMaker model/endpoint, IAM roles

**Skills tested:** SageMaker operations, data drift detection, model retraining, ML monitoring

**Estimated cost:** ~$3-5/day when endpoint is running (SageMaker ml.m5.xlarge)

---

## Prerequisites

1. **AWS Account** with admin access (or sufficient IAM permissions)
2. **Terraform** v1.5+ installed ([install guide](https://developer.hashicorp.com/terraform/install))
3. **AWS CLI** configured with credentials (`aws configure`)
4. **Python 3.9+** with boto3 (for Lab 03)

## Quick Start

```bash
# Clone or download this repository
cd Cloud_Troubleshooting_Labs

# Pick a lab
cd 01-cloud-engineer-multi-az

# Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Deploy the broken infrastructure
terraform init
terraform plan
terraform apply

# Now follow the simulation guide document to find and fix the bugs!

# IMPORTANT: Destroy when done to avoid charges
terraform destroy
```

## How Each Lab Works

1. **Deploy** — Run `terraform apply` to spin up the intentionally broken infrastructure
2. **Investigate** — Use the AWS Console and CLI to find what's wrong
3. **Fix** — Modify the Terraform code to fix the bugs
4. **Apply** — Run `terraform apply` again to deploy your fixes
5. **Verify** — Confirm everything works correctly
6. **Destroy** — Run `terraform destroy` when done

## Lab Structure

```
Cloud_Troubleshooting_Labs/
├── README.md                          # This file
├── 01-cloud-engineer-multi-az/
│   ├── main.tf                        # Broken infrastructure (5 bugs)
│   ├── variables.tf                   # Input variables
│   └── terraform.tfvars.example       # Example variable values
├── 02-devops-cicd-pipeline/
│   ├── main.tf                        # Broken pipeline (7 bugs)
│   ├── variables.tf                   # Input variables
│   └── app/                           # Sample application
│       ├── Dockerfile                 # Container definition
│       ├── package.json               # Node.js dependencies
│       ├── buildspec.yml              # CodeBuild spec (no tests!)
│       ├── src/
│       │   ├── server.js              # Working version
│       │   ├── server-broken.js       # Broken version (rename to trigger bug)
│       │   └── checkout/
│       │       └── payment-handler.js # Renamed module (was payment-processor.js)
│       └── tests/
│           └── test.js                # Tests that catch the bug
└── 03-ai-ml-sagemaker/
    ├── main.tf                        # Broken ML infrastructure (5 bugs)
    ├── variables.tf                   # Input variables
    └── training_notebook.py           # Script to train model & generate data
```

## Cost Management

These labs use real AWS resources that cost money. To minimize costs:

- **Deploy only one lab at a time**
- **Destroy resources when done:** `terraform destroy`
- **Use t3.micro instances** (default) for EC2
- **Lab 03 is the most expensive** — the SageMaker endpoint runs continuously
- **Set a billing alarm** in AWS to alert you if costs exceed your budget

Estimated total if you run all 3 labs for one day: **$6-10**

## Answer Keys

Each `main.tf` file has an answer key at the bottom (clearly marked). Try to find the bugs yourself first! The companion simulation guide documents have full step-by-step walkthroughs.

---

**Level Up in Tech** — Building the Next Generation of Cloud Engineers
