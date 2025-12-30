# =============================================================================
# VPC Peering for Wazuh Agent Connectivity
# =============================================================================
# This file manages VPC peering connections between the Wazuh cluster VPC
# and other VPCs that have EC2 instances running Wazuh agents.
#
# Usage:
# 1. Add peer VPC details to the 'wazuh_peer_vpcs' variable
# 2. Ensure the peer VPC's route tables are updated (either manually or via
#    separate Terraform configs for those VPCs)
# 3. Update security groups in peer VPCs to allow outbound to Wazuh ports
# =============================================================================

# Variable for peer VPCs
variable "wazuh_peer_vpcs" {
  description = "Map of VPCs to peer with the Wazuh cluster VPC"
  type = map(object({
    vpc_id         = string
    vpc_cidr       = string
    name           = string
    route_table_ids = list(string)
    # Set to true if the peer VPC is in a different AWS account
    cross_account  = optional(bool, false)
    peer_owner_id  = optional(string, "")
  }))
  default = {}

  # Example:
  # default = {
  #   "prod-app" = {
  #     vpc_id          = "vpc-0abc123def456789"
  #     vpc_cidr        = "10.100.0.0/16"
  #     name            = "Production Application VPC"
  #     route_table_ids = ["rtb-0abc123", "rtb-0def456"]
  #     cross_account   = false
  #   }
  #   "staging" = {
  #     vpc_id          = "vpc-0xyz789abc123456"
  #     vpc_cidr        = "10.101.0.0/16"
  #     name            = "Staging VPC"
  #     route_table_ids = ["rtb-0xyz789"]
  #     cross_account   = false
  #   }
  # }
}

# VPC Peering Connections
resource "aws_vpc_peering_connection" "wazuh_peers" {
  for_each = terraform.workspace == "wazuh" ? var.wazuh_peer_vpcs : {}

  vpc_id        = module.wazuh_vpc.vpc_id
  peer_vpc_id   = each.value.vpc_id
  peer_owner_id = each.value.cross_account ? each.value.peer_owner_id : null
  auto_accept   = each.value.cross_account ? false : true

  tags = {
    Name        = "${var.env_name}-wazuh-to-${each.key}-peering"
    Group       = var.env_group
    Environment = var.env_name
    PeerVPC     = each.value.name
    Side        = "Requester"
  }
}

# Auto-accept peering (only for same-account peering)
resource "aws_vpc_peering_connection_accepter" "wazuh_peers" {
  for_each = {
    for k, v in var.wazuh_peer_vpcs : k => v
    if terraform.workspace == "wazuh" && !v.cross_account
  }

  vpc_peering_connection_id = aws_vpc_peering_connection.wazuh_peers[each.key].id
  auto_accept               = true

  tags = {
    Name        = "${var.env_name}-wazuh-to-${each.key}-peering"
    Group       = var.env_group
    Environment = var.env_name
    PeerVPC     = each.value.name
    Side        = "Accepter"
  }
}

# Peering connection options (enable DNS resolution)
resource "aws_vpc_peering_connection_options" "wazuh_peers" {
  for_each = {
    for k, v in var.wazuh_peer_vpcs : k => v
    if terraform.workspace == "wazuh" && !v.cross_account
  }

  vpc_peering_connection_id = aws_vpc_peering_connection.wazuh_peers[each.key].id

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  depends_on = [aws_vpc_peering_connection_accepter.wazuh_peers]
}

# Routes from Wazuh VPC to peer VPCs (private subnets)
resource "aws_route" "wazuh_to_peers" {
  for_each = {
    for pair in flatten([
      for vpc_key, vpc in var.wazuh_peer_vpcs : [
        for rt_id in module.wazuh_vpc.private_route_table_ids : {
          key     = "${vpc_key}-${rt_id}"
          vpc_key = vpc_key
          rt_id   = rt_id
          cidr    = vpc.vpc_cidr
        }
      ]
    ]) : pair.key => pair
    if terraform.workspace == "wazuh"
  }

  route_table_id            = each.value.rt_id
  destination_cidr_block    = each.value.cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.wazuh_peers[each.value.vpc_key].id
}

# Routes from peer VPCs to Wazuh VPC
# NOTE: This only works if this Terraform has access to the peer VPC's route tables
# For cross-account or separately managed VPCs, these routes must be added separately
resource "aws_route" "peers_to_wazuh" {
  for_each = {
    for pair in flatten([
      for vpc_key, vpc in var.wazuh_peer_vpcs : [
        for rt_id in vpc.route_table_ids : {
          key     = "${vpc_key}-${rt_id}"
          vpc_key = vpc_key
          rt_id   = rt_id
        }
      ]
    ]) : pair.key => pair
    if terraform.workspace == "wazuh"
  }

  route_table_id            = each.value.rt_id
  destination_cidr_block    = var.wazuh_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.wazuh_peers[each.value.vpc_key].id
}

# Security group rules to allow agent traffic from peered VPCs
resource "aws_vpc_security_group_ingress_rule" "wazuh_agent_from_peer" {
  for_each = terraform.workspace == "wazuh" ? var.wazuh_peer_vpcs : {}

  security_group_id = aws_security_group.wazuh_cluster.id
  description       = "Wazuh agent traffic from ${each.value.name}"

  from_port   = 1514
  to_port     = 1514
  ip_protocol = "tcp"
  cidr_ipv4   = each.value.vpc_cidr

  tags = {
    Name    = "wazuh-agent-from-${each.key}"
    PeerVPC = each.value.name
  }
}

resource "aws_vpc_security_group_ingress_rule" "wazuh_registration_from_peer" {
  for_each = terraform.workspace == "wazuh" ? var.wazuh_peer_vpcs : {}

  security_group_id = aws_security_group.wazuh_cluster.id
  description       = "Wazuh agent registration from ${each.value.name}"

  from_port   = 1515
  to_port     = 1515
  ip_protocol = "tcp"
  cidr_ipv4   = each.value.vpc_cidr

  tags = {
    Name    = "wazuh-registration-from-${each.key}"
    PeerVPC = each.value.name
  }
}

# Outputs
output "vpc_peering_connections" {
  description = "VPC peering connection details"
  value = {
    for k, v in aws_vpc_peering_connection.wazuh_peers : k => {
      id          = v.id
      status      = v.accept_status
      peer_vpc_id = v.peer_vpc_id
      peer_cidr   = var.wazuh_peer_vpcs[k].vpc_cidr
    }
  }
}

output "peer_vpc_agent_config" {
  description = "Configuration info for agents in peer VPCs"
  value = terraform.workspace == "wazuh" ? {
    wazuh_manager_ip = try([
      for k, v in aws_instance.wazuh_server_ec2 : v.private_ip
      if v.tags["NodeType"] == "master"
    ][0], null)
    wazuh_worker_ips = [
      for k, v in aws_instance.wazuh_server_ec2 : v.private_ip
      if v.tags["NodeType"] == "worker"
    ]
    agent_registration_port = 1515
    agent_communication_port = 1514
    required_outbound_rules = <<-EOT
      # Add these outbound rules to security groups in peer VPCs:
      # TCP 1514 to ${var.wazuh_vpc_cidr} (agent events)
      # TCP 1515 to ${var.wazuh_vpc_cidr} (agent registration)
    EOT
  } : null
}
