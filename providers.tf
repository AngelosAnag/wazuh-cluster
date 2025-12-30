# =============================================================================
# Terraform and Provider Configuration
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "wazuh-tf-state"
    key            = "wazuh-cluster/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Terraform   = "true"
        Project     = "wazuh-cluster"
        Environment = var.env_name
        ManagedBy   = "terraform"
      },
      var.additional_tags
    )
  }
}
