###############################################################################
# 01-Infrastructure: VPC, Subnets, Security Groups, Endpoints
###############################################################################

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "wazuh"
      Environment = var.environment
      ManagedBy   = "terraform"
      Layer       = "infrastructure"
    }
  }
}

###############################################################################
# VPC using terraform-aws-modules
###############################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "wazuh-${var.environment}-vpc"
  cidr = var.vpc_cidr

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = [cidrsubnet(var.vpc_cidr, 8, 0), cidrsubnet(var.vpc_cidr, 8, 1), cidrsubnet(var.vpc_cidr, 8, 2)]
  public_subnets  = [cidrsubnet(var.vpc_cidr, 8, 100), cidrsubnet(var.vpc_cidr, 8, 101), cidrsubnet(var.vpc_cidr, 8, 102)]

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs (PCI compliance)
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  tags = {
    Name = "wazuh-${var.environment}-vpc"
  }
}

###############################################################################
# VPC Endpoints for SSM (no NAT needed for SSM traffic)
###############################################################################

module "vpc_endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 5.0"

  vpc_id = module.vpc.vpc_id

  endpoints = {
    s3 = {
      service         = "s3"
      service_type    = "Gateway"
      route_table_ids = module.vpc.private_route_table_ids
      tags            = { Name = "wazuh-${var.environment}-s3-endpoint" }
    }
    ssm = {
      service             = "ssm"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
      tags                = { Name = "wazuh-${var.environment}-ssm-endpoint" }
    }
    ssmmessages = {
      service             = "ssmmessages"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
      tags                = { Name = "wazuh-${var.environment}-ssmmessages-endpoint" }
    }
    ec2messages = {
      service             = "ec2messages"
      private_dns_enabled = true
      subnet_ids          = module.vpc.private_subnets
      security_group_ids  = [aws_security_group.vpc_endpoints.id]
      tags                = { Name = "wazuh-${var.environment}-ec2messages-endpoint" }
    }
  }

  tags = {
    Environment = var.environment
  }
}

###############################################################################
# Security Groups
###############################################################################

# VPC Endpoints Security Group
resource "aws_security_group" "vpc_endpoints" {
  name        = "wazuh-${var.environment}-vpc-endpoints"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wazuh-${var.environment}-vpc-endpoints-sg"
  }
}

# Wazuh Nodes Security Group
resource "aws_security_group" "wazuh_nodes" {
  name        = "wazuh-${var.environment}-nodes"
  description = "Security group for Wazuh cluster nodes"
  vpc_id      = module.vpc.vpc_id

  # Agent registration (from VPC)
  ingress {
    description = "Agent registration"
    from_port   = 1514
    to_port     = 1514
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Agent events (from VPC)
  ingress {
    description = "Agent events"
    from_port   = 1515
    to_port     = 1515
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Manager cluster communication (between nodes)
  ingress {
    description = "Manager cluster"
    from_port   = 1516
    to_port     = 1516
    protocol    = "tcp"
    self        = true
  }

  # Wazuh API
  ingress {
    description = "Wazuh API"
    from_port   = 55000
    to_port     = 55000
    protocol    = "tcp"
    self        = true
  }

  # Indexer REST API (between nodes)
  ingress {
    description = "Indexer REST API"
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    self        = true
  }

  # Indexer cluster communication (between nodes)
  ingress {
    description = "Indexer cluster"
    from_port   = 9300
    to_port     = 9300
    protocol    = "tcp"
    self        = true
  }

  # Dashboard (from ALB)
  ingress {
    description     = "Dashboard from ALB"
    from_port       = 443
    to_port         = 443
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
    Name = "wazuh-${var.environment}-nodes-sg"
  }
}

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "wazuh-${var.environment}-alb"
  description = "Security group for Wazuh Dashboard ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from allowed CIDRs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wazuh-${var.environment}-alb-sg"
  }
}

# NLB doesn't use security groups - traffic passes through to target SG
