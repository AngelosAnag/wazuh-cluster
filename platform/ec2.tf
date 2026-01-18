###############################################################################
# Platform Module - EC2 Instances, NLB, ALB
###############################################################################

terraform {
  required_version = ">= 1.0.0"

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
# Get current region
data "aws_region" "current" {}

###############################################################################
# IAM Role for EC2 Instances (SSM access)
###############################################################################

resource "aws_iam_role" "wazuh_node" {
  name = "wazuh-${var.environment}-node-role"

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

  tags = {
    Name        = "wazuh-${var.environment}-node-role"
    Environment = var.environment
  }
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
  name = "wazuh-${var.environment}-node-profile"
  role = aws_iam_role.wazuh_node.name
}

###############################################################################
# Wazuh Node Configuration
###############################################################################

locals {
  wazuh_nodes = {
    "node-1" = {
      az              = var.private_subnet_ids[0]
      role            = "manager-master-indexer"
      manager_enabled = true
      manager_type    = "master"
    }
    "node-2" = {
      az              = var.private_subnet_ids[1]
      role            = "manager-worker-indexer"
      manager_enabled = true
      manager_type    = "worker"
    }
    "node-3" = {
      az              = var.private_subnet_ids[2]
      role            = "indexer-dashboard"
      manager_enabled = false
      manager_type    = null
    }
  }
}

###############################################################################
# EC2 Instances (terraform-aws-modules/ec2-instance/aws)
###############################################################################

module "wazuh_nodes" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 5.0"

  for_each = local.wazuh_nodes

  name = "wazuh-${var.environment}-${each.key}"

  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name != "" ? var.key_name : null
  monitoring             = true
  subnet_id              = each.value.az
  vpc_security_group_ids = [var.wazuh_node_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.wazuh_node.name

  # Root volume
  root_block_device = [
    {
      volume_type           = "gp3"
      volume_size           = 50
      delete_on_termination = true
      encrypted             = true
    }
  ]

  # Data volume for Wazuh
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

  # Enable detailed monitoring
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = 1
  }

  # User data for initial setup
  user_data = templatefile("${path.module}/templates/user_data.sh", {
    node_name    = each.key
    node_role    = each.value.role
    manager_type = coalesce(each.value.manager_type, "none")
    environment  = var.environment
    ebs_device   = "/dev/nvme1n1"
  })

  tags = {
    Name           = "wazuh-${var.environment}-${each.key}"
    Environment    = var.environment
    WazuhRole      = each.value.role
    WazuhNodeName  = each.key
    ManagerEnabled = each.value.manager_enabled
    ManagerType    = each.value.manager_type != null ? each.value.manager_type : "none"
  }
}
