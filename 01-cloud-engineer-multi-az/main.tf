###############################################################################
# LEVEL UP IN TECH - CLOUD ENGINEER TROUBLESHOOTING LAB
# "Multi-AZ Architecture Failure"
#
# THIS INFRASTRUCTURE IS INTENTIONALLY BROKEN.
# Your job: Deploy it, find the 5 architectural flaws, and fix them.
#
# What this deploys:
#   - VPC with public/private subnets across 2 AZs
#   - Application Load Balancer
#   - Auto Scaling Group with EC2 instances running a simple web app
#   - RDS MySQL database
#   - NAT Gateway for private subnet internet access
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

data "aws_availability_zones" "available" {
  state = "available"
}

# ─────────────────────────────────────────────
# VPC & Networking
# ─────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
    Lab  = "cloud-engineer-multi-az"
  }
}

# Public Subnets (2 AZs)
resource "aws_subnet" "public_1a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-1a"
  }
}

resource "aws_subnet" "public_1b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-1b"
  }
}

# Private Subnets (2 AZs)
resource "aws_subnet" "private_1a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.project_name}-private-1a"
  }
}

resource "aws_subnet" "private_1b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${var.project_name}-private-1b"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# Public Route Table (correct - routes to IGW)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_1a" {
  subnet_id      = aws_subnet.public_1a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_1b" {
  subnet_id      = aws_subnet.public_1b.id
  route_table_id = aws_route_table.public.id
}

# ─────────────────────────────────────────────
# BUG #3: Single NAT Gateway in AZ-1a only
# Both private subnets route through this one NAT Gateway.
# If AZ-1a goes down, private instances in AZ-1b lose internet.
# ─────────────────────────────────────────────

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "single" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1a.id # Only in AZ-1a!

  tags = {
    Name = "${var.project_name}-nat-gw"
  }

  depends_on = [aws_internet_gateway.main]
}

# Private Route Table for AZ-1a
resource "aws_route_table" "private_1a" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.single.id
  }

  tags = {
    Name = "${var.project_name}-private-rt-1a"
  }
}

resource "aws_route_table_association" "private_1a" {
  subnet_id      = aws_subnet.private_1a.id
  route_table_id = aws_route_table.private_1a.id
}

# Private Route Table for AZ-1b — ALSO points to the single NAT in AZ-1a!
resource "aws_route_table" "private_1b" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.single.id # Bug: should have its own NAT in 1b
  }

  tags = {
    Name = "${var.project_name}-private-rt-1b"
  }
}

resource "aws_route_table_association" "private_1b" {
  subnet_id      = aws_subnet.private_1b.id
  route_table_id = aws_route_table.private_1b.id
}

# ─────────────────────────────────────────────
# Security Groups
# ─────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-alb-"
  description = "Allow HTTP/HTTPS to ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_security_group" "web" {
  name_prefix = "${var.project_name}-web-"
  description = "Allow traffic from ALB to web instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-rds-"
  description = "Allow MySQL from web tier"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# ─────────────────────────────────────────────
# Application Load Balancer (correctly configured across 2 AZs)
# ─────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_1a.id, aws_subnet.public_1b.id]

  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "web" {
  name     = "${var.project_name}-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-web-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ─────────────────────────────────────────────
# BUG #1: Auto Scaling Group — only uses AZ-1a
# The ASG is configured with only 1 subnet.
# If AZ-1a goes down, ASG cannot launch instances in AZ-1b.
# ─────────────────────────────────────────────

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-web-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd

    # Create a health check page
    cat > /var/www/html/index.html <<'HTML'
    <!DOCTYPE html>
    <html>
    <head><title>Healthcare Platform</title></head>
    <body>
      <h1>Healthcare SaaS Platform</h1>
      <p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>
      <p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>
      <p>Status: Healthy</p>
    </body>
    </html>
    HTML

    # Simulate database connectivity check
    cat > /var/www/html/api/health <<'HTML'
    {"status": "healthy", "database": "connected"}
    HTML
    mkdir -p /var/www/html/api
    cp /var/www/html/index.html /var/www/html/api/health
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-web-instance"
      Lab  = "cloud-engineer-multi-az"
    }
  }
}

resource "aws_autoscaling_group" "web" {
  name                = "${var.project_name}-web-asg"
  desired_capacity    = 2
  min_size            = 2
  max_size            = 4
  target_group_arns   = [aws_lb_target_group.web.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  # BUG: Only deploying to AZ-1a subnet!
  # This should include BOTH private subnets across AZs.
  vpc_zone_identifier = [
    aws_subnet.private_1a.id,
    # aws_subnet.private_1b.id,  # <-- THIS IS MISSING! Students need to add this.
  ]

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-web"
    propagate_at_launch = true
  }
}

# ─────────────────────────────────────────────
# BUG #2: RDS — Single-AZ (not Multi-AZ)
# If AZ-1a goes down, the database is unreachable.
# No standby replica exists for automatic failover.
# ─────────────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [aws_subnet.private_1a.id, aws_subnet.private_1b.id]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

resource "aws_db_instance" "main" {
  identifier     = "${var.project_name}-db"
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"

  db_name  = "healthcaredb"
  username = "admin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # BUG: Multi-AZ is DISABLED! No automatic failover.
  multi_az = false # <-- Students need to change this to true

  # BUG #5 (partial): No enhanced monitoring, no performance insights
  monitoring_interval          = 0 # Should be 60 for enhanced monitoring
  performance_insights_enabled = false

  backup_retention_period = 7
  skip_final_snapshot     = true

  tags = {
    Name = "${var.project_name}-db"
    Lab  = "cloud-engineer-multi-az"
  }
}

# ─────────────────────────────────────────────
# BUG #4 & #5: No Route 53 health checks, no CloudWatch alarms
# There is ZERO monitoring or alerting configured.
# The team would have no idea if the application went down.
# ─────────────────────────────────────────────

# NOTE: No aws_cloudwatch_metric_alarm resources exist.
# NOTE: No aws_route53_health_check resources exist.
# Students need to add these. See the simulation guide for specifics.


# ─────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "rds_endpoint" {
  description = "RDS database endpoint"
  value       = aws_db_instance.main.endpoint
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.web.name
}

output "nat_gateway_id" {
  description = "NAT Gateway ID (only one — that's a bug!)"
  value       = aws_nat_gateway.single.id
}


###############################################################################
# ANSWER KEY — DO NOT READ UNTIL YOU'VE TRIED TO FIND THE BUGS
###############################################################################
#
# Bug #1: ASG only has 1 subnet (line ~260)
#   FIX: Add aws_subnet.private_1b.id to vpc_zone_identifier
#
# Bug #2: RDS multi_az = false (line ~299)
#   FIX: Change multi_az to true
#
# Bug #3: Single NAT Gateway in AZ-1a (line ~118)
#   FIX: Create a second NAT Gateway in public_1b, create a second
#        route table for private_1b pointing to the new NAT
#
# Bug #4: No Route 53 health checks
#   FIX: Add aws_route53_health_check resource targeting the ALB
#
# Bug #5: No CloudWatch alarms
#   FIX: Add aws_cloudwatch_metric_alarm resources for:
#        - ALB 5XX errors
#        - ALB healthy host count
#        - RDS CPU utilization
#        - RDS free storage space
###############################################################################
