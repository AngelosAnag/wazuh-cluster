
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "angelos-test-terraform-state"
    key          = "wazuh-cluster-test/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "wazuh-cluster"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

module "infrastructure" {
  source = "./infrastructure"

  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)

  # Allowed IPs for dashboard access
  allowed_cidr_blocks = var.allowed_cidr_blocks
}

module "platform" {
  source = "./platform"

  environment        = var.environment
  vpc_id             = module.infrastructure.vpc_id
  private_subnet_ids = module.infrastructure.private_subnet_ids
  public_subnet_ids  = module.infrastructure.public_subnet_ids

  # Security groups from infrastructure
  wazuh_node_sg_id = module.infrastructure.wazuh_node_sg_id
  alb_sg_id        = module.infrastructure.alb_sg_id

  # EC2 configuration
  instance_type       = var.instance_type
  key_name            = var.key_name
  ebs_volume_size     = var.ebs_volume_size
  acm_certificate_arn = var.acm_certificate_arn

  depends_on = [module.infrastructure]
}
