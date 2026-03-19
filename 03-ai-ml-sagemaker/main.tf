###############################################################################
# LEVEL UP IN TECH - AI/ML ENGINEER TROUBLESHOOTING LAB
# "Production SageMaker Model Failure"
#
# THIS INFRASTRUCTURE IS INTENTIONALLY BROKEN.
# Your job: Deploy it, observe the failures, and fix them.
#
# What this deploys:
#   - S3 buckets for training data, model artifacts, and monitoring
#   - SageMaker execution role with required permissions
#   - SageMaker Model (using a pre-built XGBoost container)
#   - SageMaker Endpoint Configuration (undersized, single instance)
#   - SageMaker Endpoint (real-time inference)
#   - CloudWatch Log Group for endpoint logs
#
# Hidden bugs (DO NOT READ until you've tried to find them yourself):
#   Scroll to the bottom of this file for the answer key.
#
# COST WARNING: SageMaker endpoints cost money while running.
#   Remember to run `terraform destroy` when you're done!
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
# S3 Buckets
# ─────────────────────────────────────────────

resource "aws_s3_bucket" "ml_data" {
  bucket        = "${var.project_name}-data-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-data"
    Lab  = "ai-ml-sagemaker"
  }
}

resource "aws_s3_bucket" "ml_models" {
  bucket        = "${var.project_name}-models-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-models"
    Lab  = "ai-ml-sagemaker"
  }
}

resource "aws_s3_bucket" "ml_monitoring" {
  bucket        = "${var.project_name}-monitoring-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-monitoring"
    Lab  = "ai-ml-sagemaker"
  }
}

# Create folder structure in data bucket
resource "aws_s3_object" "training_folder" {
  bucket  = aws_s3_bucket.ml_data.id
  key     = "training/"
  content = ""
}

resource "aws_s3_object" "production_folder" {
  bucket  = aws_s3_bucket.ml_data.id
  key     = "production/"
  content = ""
}

resource "aws_s3_object" "retrain_folder" {
  bucket  = aws_s3_bucket.ml_data.id
  key     = "retrain/"
  content = ""
}

# ─────────────────────────────────────────────
# IAM Role for SageMaker
# ─────────────────────────────────────────────

resource "aws_iam_role" "sagemaker_execution" {
  name = "${var.project_name}-sagemaker-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "sagemaker.amazonaws.com" }
    }]
  })

  tags = { Name = "${var.project_name}-sagemaker-role" }
}

resource "aws_iam_role_policy" "sagemaker_s3" {
  name = "${var.project_name}-sagemaker-s3"
  role = aws_iam_role.sagemaker_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:ListBucket",
          "s3:DeleteObject", "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.ml_data.arn,
          "${aws_s3_bucket.ml_data.arn}/*",
          aws_s3_bucket.ml_models.arn,
          "${aws_s3_bucket.ml_models.arn}/*",
          aws_s3_bucket.ml_monitoring.arn,
          "${aws_s3_bucket.ml_monitoring.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:CreateLogStream",
          "logs:PutLogEvents", "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────────
# CloudWatch Log Group
# ─────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "sagemaker" {
  name              = "/aws/sagemaker/Endpoints/${var.project_name}-fraud-detection"
  retention_in_days = 14

  tags = { Name = "${var.project_name}-sagemaker-logs" }
}

# ─────────────────────────────────────────────
# SageMaker Model
# Uses the pre-built AWS XGBoost container image.
# In a real lab, students will train a model and deploy it here.
# ─────────────────────────────────────────────

# Get the XGBoost container image URI for the region
locals {
  # XGBoost container image URIs by region
  xgboost_images = {
    "us-east-1" = "683313688378.dkr.ecr.us-east-1.amazonaws.com/sagemaker-xgboost:1.5-1"
    "us-east-2" = "257758044811.dkr.ecr.us-east-2.amazonaws.com/sagemaker-xgboost:1.5-1"
    "us-west-1" = "746614075791.dkr.ecr.us-west-1.amazonaws.com/sagemaker-xgboost:1.5-1"
    "us-west-2" = "246618743249.dkr.ecr.us-west-2.amazonaws.com/sagemaker-xgboost:1.5-1"
  }
}

# NOTE: The SageMaker Model and Endpoint below require a trained model artifact
# in S3. Students will first run the training notebook to create the model,
# then these resources will be deployed.
#
# For initial deploy, we create the supporting infrastructure only.
# The endpoint resources are defined but commented out until a model exists.

# ─────────────────────────────────────────────
# BUG #1: Endpoint Config — single instance, undersized
# A single ml.m5.xlarge cannot handle 2,000 requests/minute.
# No auto-scaling is configured.
# ─────────────────────────────────────────────

resource "aws_sagemaker_endpoint_configuration" "fraud_detection" {
  count = var.deploy_endpoint ? 1 : 0
  name  = "${var.project_name}-fraud-detection-config"

  production_variants {
    variant_name           = "AllTraffic"
    model_name             = aws_sagemaker_model.fraud_detection[0].name
    instance_type          = "ml.m5.xlarge"
    initial_instance_count = 1 # BUG: Only 1 instance for 2000 req/min!

    # BUG #2: No data capture configured!
    # Without data capture, you can't detect data drift.
    # Students need to add:
    # data_capture_config {
    #   enable_capture              = true
    #   initial_sampling_percentage = 20
    #   destination_s3_uri          = "s3://${aws_s3_bucket.ml_monitoring.id}/data-capture/"
    #   capture_options {
    #     capture_mode = "Input"
    #   }
    #   capture_options {
    #     capture_mode = "Output"
    #   }
    # }
  }

  tags = { Name = "${var.project_name}-endpoint-config" }
}

resource "aws_sagemaker_model" "fraud_detection" {
  count              = var.deploy_endpoint ? 1 : 0
  name               = "${var.project_name}-fraud-detection"
  execution_role_arn = aws_iam_role.sagemaker_execution.arn

  primary_container {
    image          = local.xgboost_images[var.aws_region]
    model_data_url = "s3://${aws_s3_bucket.ml_models.id}/model/model.tar.gz"
  }

  tags = { Name = "${var.project_name}-model" }
}

resource "aws_sagemaker_endpoint" "fraud_detection" {
  count                = var.deploy_endpoint ? 1 : 0
  name                 = "${var.project_name}-fraud-detection"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.fraud_detection[0].name

  tags = { Name = "${var.project_name}-endpoint" }
}

# ─────────────────────────────────────────────
# BUG #3: No auto-scaling on the endpoint
# Students need to add aws_appautoscaling_target and
# aws_appautoscaling_policy resources.
# ─────────────────────────────────────────────

# MISSING: aws_appautoscaling_target for sagemaker endpoint
# MISSING: aws_appautoscaling_policy with target tracking
# Students should add:
#
# resource "aws_appautoscaling_target" "sagemaker" {
#   max_capacity       = 6
#   min_capacity       = 2
#   resource_id        = "endpoint/${var.project_name}-fraud-detection/variant/AllTraffic"
#   scalable_dimension = "sagemaker:variant:DesiredInstanceCount"
#   service_namespace  = "sagemaker"
# }
#
# resource "aws_appautoscaling_policy" "sagemaker" {
#   name               = "${var.project_name}-scaling-policy"
#   policy_type        = "TargetTrackingScaling"
#   resource_id        = aws_appautoscaling_target.sagemaker.resource_id
#   scalable_dimension = aws_appautoscaling_target.sagemaker.scalable_dimension
#   service_namespace  = aws_appautoscaling_target.sagemaker.service_namespace
#
#   target_tracking_scaling_policy_configuration {
#     predefined_metric_specification {
#       predefined_metric_type = "SageMakerVariantInvocationsPerInstance"
#     }
#     target_value       = 750.0
#     scale_in_cooldown  = 300
#     scale_out_cooldown = 60
#   }
# }


# ─────────────────────────────────────────────
# BUG #4: No Model Monitor schedule
# Data drift goes undetected for months.
# ─────────────────────────────────────────────

# MISSING: aws_sagemaker_model_package_group (for model versioning)
# MISSING: aws_sagemaker_monitoring_schedule (for drift detection)
# MISSING: Baseline statistics and constraints in S3
#
# Students should add SageMaker Model Monitor using the Python SDK
# (Terraform support for Model Monitor is limited; use a notebook)


# ─────────────────────────────────────────────
# BUG #5: No CloudWatch alarms for the ML endpoint
# ─────────────────────────────────────────────

# MISSING: CloudWatch alarm for Invocation5XXErrors
# MISSING: CloudWatch alarm for ModelLatency
# MISSING: CloudWatch alarm for OverheadLatency
# MISSING: SNS topic for ML team alerts
#
# Students need to add:
#
# resource "aws_sns_topic" "ml_alerts" {
#   name = "${var.project_name}-ml-alerts"
# }
#
# resource "aws_cloudwatch_metric_alarm" "endpoint_5xx" {
#   alarm_name          = "${var.project_name}-endpoint-5xx"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = 2
#   metric_name         = "Invocation5XXErrors"
#   namespace           = "AWS/SageMaker"
#   period              = 300
#   statistic           = "Sum"
#   threshold           = 50
#   alarm_actions       = [aws_sns_topic.ml_alerts.arn]
#
#   dimensions = {
#     EndpointName = "${var.project_name}-fraud-detection"
#     VariantName  = "AllTraffic"
#   }
# }
#
# resource "aws_cloudwatch_metric_alarm" "model_latency" {
#   alarm_name          = "${var.project_name}-model-latency"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = 3
#   metric_name         = "ModelLatency"
#   namespace           = "AWS/SageMaker"
#   period              = 300
#   statistic           = "Average"
#   threshold           = 500000
#   alarm_actions       = [aws_sns_topic.ml_alerts.arn]
#
#   dimensions = {
#     EndpointName = "${var.project_name}-fraud-detection"
#     VariantName  = "AllTraffic"
#   }
# }


# ─────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────

output "data_bucket" {
  description = "S3 bucket for training and production data"
  value       = aws_s3_bucket.ml_data.id
}

output "models_bucket" {
  description = "S3 bucket for model artifacts"
  value       = aws_s3_bucket.ml_models.id
}

output "monitoring_bucket" {
  description = "S3 bucket for monitoring data (data capture, baselines)"
  value       = aws_s3_bucket.ml_monitoring.id
}

output "sagemaker_execution_role_arn" {
  description = "SageMaker execution role ARN (use in notebooks)"
  value       = aws_iam_role.sagemaker_execution.arn
}

output "endpoint_name" {
  description = "SageMaker endpoint name (once deployed)"
  value       = var.deploy_endpoint ? aws_sagemaker_endpoint.fraud_detection[0].name : "Not deployed yet"
}


###############################################################################
# ANSWER KEY — DO NOT READ UNTIL YOU'VE TRIED TO FIND THE BUGS
###############################################################################
#
# Bug #1: Single instance endpoint (line ~175)
#   FIX: Change initial_instance_count to 2 (minimum)
#        Add auto-scaling (see Bug #3)
#
# Bug #2: No data capture on endpoint (line ~178)
#   FIX: Uncomment and configure the data_capture_config block
#        This captures request/response data for drift analysis
#
# Bug #3: No auto-scaling (line ~211)
#   FIX: Add aws_appautoscaling_target (min=2, max=6)
#        Add aws_appautoscaling_policy with target tracking
#        at 750 invocations per instance
#
# Bug #4: No Model Monitor (line ~238)
#   FIX: Set up SageMaker Model Monitor via Python SDK:
#        - Generate baseline statistics from training data
#        - Create a monitoring schedule (hourly)
#        - Configure drift detection thresholds
#
# Bug #5: No CloudWatch alarms (line ~255)
#   FIX: Add alarms for:
#        - Invocation5XXErrors > 50 in 5 minutes
#        - ModelLatency > 500ms average
#        - InvocationsPerInstance (capacity planning)
#        Wire alarms to an SNS topic for the ML team
###############################################################################
