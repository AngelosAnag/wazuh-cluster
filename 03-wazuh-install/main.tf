###############################################################################
# 03-Wazuh-Install: SSM Documents for Wazuh Cluster Installation
###############################################################################

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = local.platform.aws_region

  default_tags {
    tags = {
      Project     = "wazuh"
      Environment = local.platform.environment
      ManagedBy   = "terraform"
      Layer       = "wazuh-install"
    }
  }
}

###############################################################################
# Remote State from 02-platform
###############################################################################

data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "wazuh/02-platform/terraform.tfstate"
    region = var.aws_region
  }
}

locals {
  platform = data.terraform_remote_state.platform.outputs
  env      = local.platform.environment
}

###############################################################################
# Random Cluster Key
###############################################################################

resource "random_password" "cluster_key" {
  length  = 32
  special = false
}

###############################################################################
# SSM Documents
###############################################################################

resource "aws_ssm_document" "generate_certificates" {
  name            = "Wazuh-GenerateCertificates-${local.env}"
  document_type   = "Command"
  document_format = "YAML"
  content         = file("${path.module}/ssm-documents/01-generate-certificates.yaml")

  # Allow updates to the document
}

resource "aws_ssm_document" "distribute_certificates" {
  name            = "Wazuh-DistributeCertificates-${local.env}"
  document_type   = "Command"
  document_format = "YAML"
  content         = file("${path.module}/ssm-documents/02-distribute-certificates.yaml")

}

resource "aws_ssm_document" "install_indexer" {
  name            = "Wazuh-InstallIndexer-${local.env}"
  document_type   = "Command"
  document_format = "YAML"
  content         = file("${path.module}/ssm-documents/03-install-indexer.yaml")

}

resource "aws_ssm_document" "initialize_indexer_cluster" {
  name            = "Wazuh-InitializeIndexerCluster-${local.env}"
  document_type   = "Command"
  document_format = "YAML"
  content         = file("${path.module}/ssm-documents/04-initialize-indexer-cluster.yaml")

}

resource "aws_ssm_document" "install_manager" {
  name            = "Wazuh-InstallManager-${local.env}"
  document_type   = "Command"
  document_format = "YAML"
  content         = file("${path.module}/ssm-documents/05-install-manager.yaml")

}

resource "aws_ssm_document" "install_dashboard" {
  name            = "Wazuh-InstallDashboard-${local.env}"
  document_type   = "Command"
  document_format = "YAML"
  content         = file("${path.module}/ssm-documents/06-install-dashboard.yaml")

}
