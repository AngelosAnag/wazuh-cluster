###############################################################################
# 02-Platform: EC2 Instances, NLB, ALB, IAM Roles
###############################################################################

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "random" {
}

provider "aws" {
  region = local.infra.aws_region

  default_tags {
    tags = {
      Project     = "wazuh"
      Environment = local.infra.environment
      ManagedBy   = "terraform"
      Layer       = "platform"
    }
  }
}

###############################################################################
# Remote State from 01-infrastructure
###############################################################################

data "terraform_remote_state" "infrastructure" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "wazuh/01-infrastructure/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  infra = data.terraform_remote_state.infrastructure.outputs
}

###############################################################################
# Data Sources
###############################################################################

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

###############################################################################
# IAM Role for EC2 Instances
###############################################################################

resource "aws_iam_role" "wazuh_node" {
  name = "wazuh-${local.infra.environment}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.wazuh_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.wazuh_node.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "wazuh_node" {
  name = "wazuh-${local.infra.environment}-node-profile"
  role = aws_iam_role.wazuh_node.name
}

# S3 access for certificates
resource "aws_iam_role_policy" "s3_access" {
  name = "wazuh-${local.infra.environment}-s3-access"
  role = aws_iam_role.wazuh_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.wazuh_artifacts.arn,
          "${aws_s3_bucket.wazuh_artifacts.arn}/*"
        ]
      }
    ]
  })
}

###############################################################################
# S3 Bucket for Certificates
###############################################################################

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "wazuh_artifacts" {
  bucket = "wazuh-${local.infra.environment}-artifacts-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_versioning" "wazuh_artifacts" {
  bucket = aws_s3_bucket.wazuh_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "wazuh_artifacts" {
  bucket = aws_s3_bucket.wazuh_artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "wazuh_artifacts" {
  bucket                  = aws_s3_bucket.wazuh_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

###############################################################################
# Wazuh Node Configuration
###############################################################################

locals {
  wazuh_nodes = {
    "node-1" = {
      subnet_id    = local.infra.private_subnet_ids[0]
      role         = "manager-master-indexer"
      manager_type = "master"
    }
    "node-2" = {
      subnet_id    = local.infra.private_subnet_ids[1]
      role         = "manager-worker-indexer"
      manager_type = "worker"
    }
    "node-3" = {
      subnet_id    = local.infra.private_subnet_ids[2]
      role         = "indexer-dashboard"
      manager_type = ""
    }
  }
}

###############################################################################
# EC2 Instances
###############################################################################

module "wazuh_nodes" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 5.0"

  for_each = local.wazuh_nodes

  name = "wazuh-${local.infra.environment}-${each.key}"

  create             = true
  ami                = data.aws_ami.amazon_linux.id
  ignore_ami_changes = true

  instance_type               = var.instance_type
  monitoring                  = true
  subnet_id                   = each.value.subnet_id
  vpc_security_group_ids      = [local.infra.wazuh_nodes_sg_id]
  iam_instance_profile        = aws_iam_instance_profile.wazuh_node.name
  associate_public_ip_address = false

  root_block_device = [
    {
      volume_type           = "gp3"
      volume_size           = 50
      delete_on_termination = true
      encrypted             = true
    }
  ]

  ebs_block_device = [
    {
      device_name           = "/dev/sdf"
      volume_type           = "gp3"
      volume_size           = var.ebs_volume_size
      iops                  = 3000
      throughput            = 125
      delete_on_termination = false
      encrypted             = true
    }
  ]

  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh", {
    node_name    = each.key
    node_role    = each.value.role
    manager_type = each.value.manager_type
    environment  = local.infra.environment
  }))

  tags = {
    WazuhRole     = each.value.role
    WazuhNodeName = each.key
  }
}

###############################################################################
# Network Load Balancer (for Wazuh Agents)
###############################################################################

resource "aws_lb" "nlb" {
  name               = "wazuh-${local.infra.environment}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = local.infra.private_subnet_ids

  enable_cross_zone_load_balancing = true
}

resource "aws_lb_target_group" "agent_registration" {
  name     = "wazuh-${local.infra.environment}-agent-reg"
  port     = 1514
  protocol = "TCP"
  vpc_id   = local.infra.vpc_id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = 1514
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }
}

resource "aws_lb_target_group" "agent_events" {
  name     = "wazuh-${local.infra.environment}-agent-evt"
  port     = 1515
  protocol = "TCP"
  vpc_id   = local.infra.vpc_id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = 1515
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }
}

resource "aws_lb_listener" "agent_registration" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 1514
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agent_registration.arn
  }
}

resource "aws_lb_listener" "agent_events" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 1515
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agent_events.arn
  }
}

# Attach manager nodes to NLB
resource "aws_lb_target_group_attachment" "agent_registration" {
  for_each = { for k, v in local.wazuh_nodes : k => v if v.manager_type != "" }

  target_group_arn = aws_lb_target_group.agent_registration.arn
  target_id        = module.wazuh_nodes[each.key].id
  port             = 1514
}

resource "aws_lb_target_group_attachment" "agent_events" {
  for_each = { for k, v in local.wazuh_nodes : k => v if v.manager_type != "" }

  target_group_arn = aws_lb_target_group.agent_events.arn
  target_id        = module.wazuh_nodes[each.key].id
  port             = 1515
}

###############################################################################
# Application Load Balancer (for Dashboard)
###############################################################################

resource "aws_lb" "alb" {
  name               = "wazuh-${local.infra.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [local.infra.alb_sg_id]
  subnets            = local.infra.public_subnet_ids
}

resource "aws_lb_target_group" "dashboard" {
  name     = "wazuh-${local.infra.environment}-dashboard"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = local.infra.vpc_id

  health_check {
    enabled             = true
    path                = "/app/login"
    port                = 443
    protocol            = "HTTPS"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 30
    matcher             = "200,302"
  }
}

resource "aws_lb_listener" "dashboard" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = var.acm_certificate_arn != "" ? "HTTPS" : "HTTP"
  ssl_policy        = var.acm_certificate_arn != "" ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null
  certificate_arn   = var.acm_certificate_arn != "" ? var.acm_certificate_arn : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dashboard.arn
  }
}

resource "aws_lb_target_group_attachment" "dashboard" {
  target_group_arn = aws_lb_target_group.dashboard.arn
  target_id        = module.wazuh_nodes["node-3"].id
  port             = 443
}

###############################################################################
# Route53 DNS Record for Dashboard
###############################################################################

resource "aws_route53_record" "dashboard" {
  count   = var.route53_zone_id != "" && var.domain_name != "" ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}
