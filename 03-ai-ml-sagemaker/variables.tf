variable "aws_region" {
  description = "AWS region to deploy the lab"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "luit-ml-lab"
}

variable "deploy_endpoint" {
  description = "Set to true AFTER you've trained a model and uploaded model.tar.gz to S3"
  type        = bool
  default     = false
}
