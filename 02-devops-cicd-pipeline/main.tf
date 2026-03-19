###############################################################################
# LEVEL UP IN TECH - CLOUD DEVOPS ENGINEER TROUBLESHOOTING LAB
# "Broken CI/CD Pipeline"
#
# THIS INFRASTRUCTURE IS INTENTIONALLY BROKEN.
# Your job: Deploy it, push a code change, watch it fail, then fix the pipeline.
#
# What this deploys:
#   - ECS Fargate cluster with a simple web app
#   - ECR repository for Docker images
#   - Application Load Balancer
#   - CodeBuild project (builds Docker image)
#   - CodePipeline (Source > Build > Deploy — NO test stage!)
#   - S3 bucket for pipeline artifacts
#
# Hidden bugs (DO NOT READ until you've tried to find them yourself):
#   Scroll to the bottom of this file for the answer key.
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─────────────────────────────────────────────
# VPC & Networking (simplified for this lab)
# ─────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-public-1" }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-public-2" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "pub1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "pub2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

# ─────────────────────────────────────────────
# Security Groups
# ─────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-alb-sg" }
}

resource "aws_security_group" "ecs" {
  name_prefix = "${var.project_name}-ecs-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-ecs-sg" }
}

# ─────────────────────────────────────────────
# ECR Repository
# ─────────────────────────────────────────────

resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-checkout"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false # BUG: Security scanning disabled
  }

  tags = { Name = "${var.project_name}-ecr" }
}

# ─────────────────────────────────────────────
# ECS Cluster, Task Definition, Service
# ─────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled" # BUG: Container insights disabled — no visibility
  }

  tags = { Name = "${var.project_name}-cluster" }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}-checkout"
  retention_in_days = 7

  tags = { Name = "${var.project_name}-ecs-logs" }
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_execution" {
  name = "${var.project_name}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-checkout"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn

  container_definitions = jsonencode([{
    name      = "checkout"
    image     = "${aws_ecr_repository.app.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 3000
      hostPort      = 3000
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  tags = { Name = "${var.project_name}-task-def" }
}

# ALB
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = { Name = "${var.project_name}-alb" }
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 30
    matcher             = "200"
  }

  tags = { Name = "${var.project_name}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# BUG #1: ECS Service with only 1 task (no redundancy)
# and NO deployment circuit breaker
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-checkout"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1 # BUG: Only 1 task — no redundancy!
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "checkout"
    container_port   = 3000
  }

  # BUG: No deployment circuit breaker!
  # If new tasks fail to start, the deployment hangs forever.
  # deployment_circuit_breaker {
  #   enable   = true
  #   rollback = true
  # }

  # BUG: Rolling update replaces ALL tasks at once
  deployment_minimum_healthy_percent = 0   # Allows 0 healthy tasks during deploy!
  deployment_maximum_percent         = 100 # No extra capacity during deploy

  tags = { Name = "${var.project_name}-checkout-service" }
}

# ─────────────────────────────────────────────
# CodeBuild Project
# ─────────────────────────────────────────────

resource "aws_iam_role" "codebuild" {
  name = "${var.project_name}-codebuild"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  name = "${var.project_name}-codebuild-policy"
  role = aws_iam_role.codebuild.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents",
          "ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage",
          "ecr:PutImage", "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart", "ecr:CompleteLayerUpload",
          "s3:GetObject", "s3:PutObject", "s3:GetBucketAcl",
          "s3:GetBucketLocation"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_codebuild_project" "build" {
  name          = "${var.project_name}-build"
  description   = "Build Docker image and push to ECR"
  build_timeout = 15
  service_role  = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true # Required for Docker builds
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "ECR_REPO_URI"
      value = aws_ecr_repository.app.repository_url
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }

  tags = { Name = "${var.project_name}-codebuild" }
}

# BUG #2: NO separate test CodeBuild project exists.
# The pipeline goes straight from build to deploy with zero testing.

# ─────────────────────────────────────────────
# CodePipeline
# ─────────────────────────────────────────────

resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket        = "${var.project_name}-pipeline-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = { Name = "${var.project_name}-pipeline-artifacts" }
}

resource "aws_iam_role" "codepipeline" {
  name = "${var.project_name}-codepipeline"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "${var.project_name}-codepipeline-policy"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:GetBucketVersioning",
          "codebuild:BatchGetBuilds", "codebuild:StartBuild",
          "ecs:DescribeServices", "ecs:DescribeTaskDefinition",
          "ecs:DescribeTasks", "ecs:ListTasks",
          "ecs:RegisterTaskDefinition", "ecs:UpdateService",
          "iam:PassRole", "codestar-connections:UseConnection"
        ]
        Resource = "*"
      }
    ]
  })
}

# BUG #3: Pipeline has NO test stage and NO approval gate
# Source → Build → Deploy. That's it. Broken code goes straight to prod.
resource "aws_codepipeline" "main" {
  name     = "${var.project_name}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.pipeline_artifacts.bucket
    type     = "S3"
  }

  # Stage 1: Source (GitHub via CodeStar Connection)
  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = var.codestar_connection_arn
        FullRepositoryId = var.github_repo
        BranchName       = "main"
      }
    }
  }

  # Stage 2: Build (Docker image → ECR)
  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.build.name
      }
    }
  }

  # BUG: NO Test stage here!
  # Students need to add:
  # - A CodeBuild project that runs unit/integration tests
  # - A "Test" stage between Build and Deploy
  # - An "Approval" stage before production deploy

  # Stage 3: Deploy (straight to production!)
  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["build_output"]
      version         = "1"

      configuration = {
        ClusterName = aws_ecs_cluster.main.name
        ServiceName = aws_ecs_service.app.name
        FileName    = "imagedefinitions.json"
      }
    }
  }

  tags = { Name = "${var.project_name}-pipeline" }
}

# ─────────────────────────────────────────────
# BUG #4: No deployment alarms or auto-rollback
# There are no CloudWatch alarms monitoring deployments.
# If a bad deploy causes 5XX errors, nobody knows.
# ─────────────────────────────────────────────

# NOTE: No aws_cloudwatch_metric_alarm resources exist.
# Students need to add alarms for:
# - ALB 5XX error rate
# - ECS service running task count
# - Target group healthy host count


# ─────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────

output "alb_dns_name" {
  description = "ALB DNS name — visit this to see the app"
  value       = aws_lb.main.dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL — push Docker images here"
  value       = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

output "pipeline_name" {
  description = "CodePipeline name"
  value       = aws_codepipeline.main.name
}

output "codebuild_project" {
  description = "CodeBuild project name"
  value       = aws_codebuild_project.build.name
}


###############################################################################
# ANSWER KEY — DO NOT READ UNTIL YOU'VE TRIED TO FIND THE BUGS
###############################################################################
#
# Bug #1: ECS Service — 1 task, no circuit breaker (line ~232)
#   FIX: Set desired_count = 3
#        Uncomment deployment_circuit_breaker block
#        Set deployment_minimum_healthy_percent = 50
#        Set deployment_maximum_percent = 200
#
# Bug #2: No test CodeBuild project (line ~290)
#   FIX: Create a separate aws_codebuild_project for testing
#        with a buildspec that runs: npm test, npm run lint,
#        and verifies module imports resolve
#
# Bug #3: Pipeline skips testing and approval (line ~335)
#   FIX: Add a "Test" stage after Build using the test CodeBuild project
#        Add an "Approval" stage (Manual) before Deploy
#        Optionally add a "DeployStaging" stage before Approval
#
# Bug #4: No deployment alarms (line ~379)
#   FIX: Add aws_cloudwatch_metric_alarm for:
#        - HTTPCode_Target_5XX_Count > 10 in 60 seconds
#        - HealthyHostCount < 1
#        - RunningTaskCount < desired_count
#
# Bonus Bug: ECR scanning disabled (line ~112)
#   FIX: Set scan_on_push = true
#
# Bonus Bug: Container insights disabled (line ~121)
#   FIX: Set value = "enabled"
#
# Bonus Bug: deployment_minimum_healthy_percent = 0 (line ~242)
#   This means during deployment, ALL tasks can be killed before
#   new ones are healthy. Zero downtime is impossible with this config.
###############################################################################
