###############################################################################
# Root Outputs
###############################################################################

# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.infrastructure.vpc_id
}

# Instance Outputs
output "wazuh_node_private_ips" {
  description = "Private IPs of Wazuh nodes"
  value       = module.platform.wazuh_node_private_ips
}

output "wazuh_node_ids" {
  description = "Instance IDs of Wazuh nodes"
  value       = module.platform.wazuh_node_ids
}

# Load Balancer Outputs
output "nlb_dns_name" {
  description = "DNS name of the NLB for agent registration"
  value       = module.platform.nlb_dns_name
}

output "alb_dns_name" {
  description = "DNS name of the ALB for dashboard access"
  value       = module.platform.alb_dns_name
}

output "dashboard_url" {
  description = "URL to access Wazuh Dashboard"
  value       = "https://${module.platform.alb_dns_name}"
}

# Connection Info
output "ssh_connection_commands" {
  description = "SSH commands to connect to each node (via bastion or SSM)"
  value       = module.platform.ssh_connection_info
}

# SSM Installation
output "s3_artifacts_bucket" {
  description = "S3 bucket for Wazuh certificates"
  value       = module.platform.s3_artifacts_bucket
}

output "ssm_documents" {
  description = "SSM document names for installation"
  value       = module.platform.ssm_documents
}

output "installation_commands" {
  description = "AWS CLI commands to install Wazuh via SSM"
  value       = module.platform.installation_commands
}
