# =============================================================================
# Example Terraform Variables
# =============================================================================
# Copy this file to terraform.tfvars and update with your values
# =============================================================================

aws_region = "eu-central-1"
env_name   = "playground"
env_group  = "wazuh-cluster"

# VPC Configuration
wazuh_vpc_cidr        = "10.172.0.0/16"
wazuh_private_subnets = ["10.172.11.0/24", "10.172.12.0/24"]
wazuh_public_subnets  = ["10.172.1.0/24", "10.172.2.0/24"]

# IMPORTANT: Update this to your office/home IP for SSH access to bastion
trusted_ssh_cidr = "37.6.171.169/32"

# Path to your SSH public key
ssh_public_key_path = "~/.ssh/wazuh-cluster-key.pub"

# SNS Topic for alerts (leave empty to create new, or provide existing ARN)
sns_topic_arn = ""

# VPC Peering Configuration
# Uncomment and configure to peer with other VPCs
# wazuh_peer_vpcs = {
#   "prod-app" = {
#     vpc_id          = "vpc-0abc123def456789"
#     vpc_cidr        = "10.100.0.0/16"
#     name            = "Production Application VPC"
#     route_table_ids = ["rtb-0abc123", "rtb-0def456"]
#     cross_account   = false
#   }
# }

# Additional tags
additional_tags = {
  CostCenter = "security"
  Owner      = "security-team"
}
