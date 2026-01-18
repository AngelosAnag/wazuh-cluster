###############################################################################
# Infrastructure Module Outputs
###############################################################################

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnet_cidrs" {
  description = "CIDR blocks of private subnets"
  value       = module.vpc.private_subnets_cidr_blocks
}

output "wazuh_node_sg_id" {
  description = "Security group ID for Wazuh nodes"
  value       = aws_security_group.wazuh_nodes.id
}

output "alb_sg_id" {
  description = "Security group ID for ALB"
  value       = aws_security_group.alb.id
}

output "nlb_targets_sg_id" {
  description = "Security group ID for NLB targets"
  value       = aws_security_group.nlb_targets.id
}

output "nat_gateway_ips" {
  description = "Elastic IPs of NAT Gateways"
  value       = module.vpc.nat_public_ips
}
