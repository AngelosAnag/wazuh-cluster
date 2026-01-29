###############################################################################
# Outputs for 02-Platform
# These are consumed by 03-wazuh-install via terraform_remote_state
###############################################################################

output "wazuh_node_ids" {
  description = "Instance IDs of Wazuh nodes"
  value = {
    for k, v in module.wazuh_nodes : k => v.id
  }
}

output "wazuh_node_private_ips" {
  description = "Private IPs of Wazuh nodes"
  value = {
    for k, v in module.wazuh_nodes : k => v.private_ip
  }
}

output "node1_id" {
  description = "Instance ID of node-1"
  value       = module.wazuh_nodes["node-1"].id
}

output "node2_id" {
  description = "Instance ID of node-2"
  value       = module.wazuh_nodes["node-2"].id
}

output "node3_id" {
  description = "Instance ID of node-3"
  value       = module.wazuh_nodes["node-3"].id
}

output "node1_ip" {
  description = "Private IP of node-1"
  value       = module.wazuh_nodes["node-1"].private_ip
}

output "node2_ip" {
  description = "Private IP of node-2"
  value       = module.wazuh_nodes["node-2"].private_ip
}

output "node3_ip" {
  description = "Private IP of node-3"
  value       = module.wazuh_nodes["node-3"].private_ip
}

output "s3_artifacts_bucket" {
  description = "S3 bucket for Wazuh certificates"
  value       = aws_s3_bucket.wazuh_artifacts.bucket
}

output "nlb_dns_name" {
  description = "DNS name of NLB for agent registration"
  value       = aws_lb.nlb.dns_name
}

output "alb_dns_name" {
  description = "DNS name of ALB for dashboard"
  value       = aws_lb.alb.dns_name
}

output "dashboard_url" {
  description = "URL to access Wazuh Dashboard"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "https://${aws_lb.alb.dns_name}"
}

output "domain_name" {
  description = "Custom domain name for dashboard (if configured)"
  value       = var.domain_name
}

output "ssh_commands" {
  description = "SSM commands to connect to each node"
  value = {
    for k, v in module.wazuh_nodes : k => "aws ssm start-session --target ${v.id} --region ${local.infra.aws_region}"
  }
}

output "environment" {
  description = "Environment name"
  value       = local.infra.environment
}

output "aws_region" {
  description = "AWS region"
  value       = local.infra.aws_region
}
