# VPC Module for Wazuh Cluster
module "wazuh_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  create_vpc = terraform.workspace == "wazuh"

  name = "${var.env_name}-wazuh-vpc"
  cidr = var.wazuh_vpc_cidr

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = var.wazuh_private_subnets
  public_subnets  = var.wazuh_public_subnets

  # High availability NAT Gateway setup
  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  # DNS settings
  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs
  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true
  flow_log_max_aggregation_interval    = 60
  flow_log_destination_type            = "cloud-watch-logs"
  flow_log_log_format                  = null
  flow_log_traffic_type                = "ALL"

  vpc_flow_log_tags = {
    Name = "${var.env_name}-wazuh-vpc-flow-logs"
  }

  # Subnet tagging
  private_subnet_tags = {
    Type = "Private"
    Tier = "Application"
  }

  public_subnet_tags = {
    Type = "Public"
  }

  tags = {
    Name        = "${var.env_name}-wazuh-vpc"
    Group       = var.env_group
    Environment = var.env_name
    Compliance  = "PCI-DSS"
  }
}

# VPC Endpoints - created separately for better control
resource "aws_vpc_endpoint" "s3" {
  count = terraform.workspace == "wazuh" ? 1 : 0

  vpc_id            = module.wazuh_vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.wazuh_vpc.private_route_table_ids

  tags = {
    Name        = "${var.env_name}-wazuh-s3-endpoint"
    Group       = var.env_group
    Environment = var.env_name
  }
}

resource "aws_vpc_endpoint" "ssm" {
  count = terraform.workspace == "wazuh" ? 1 : 0

  vpc_id              = module.wazuh_vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.wazuh_vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.env_name}-wazuh-ssm-endpoint"
    Group       = var.env_group
    Environment = var.env_name
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  count = terraform.workspace == "wazuh" ? 1 : 0

  vpc_id              = module.wazuh_vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.wazuh_vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.env_name}-wazuh-ssmmessages-endpoint"
    Group       = var.env_group
    Environment = var.env_name
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  count = terraform.workspace == "wazuh" ? 1 : 0

  vpc_id              = module.wazuh_vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.wazuh_vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.env_name}-wazuh-ec2messages-endpoint"
    Group       = var.env_group
    Environment = var.env_name
  }
}

# Security Group for VPC Endpoints
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.env_name}-wazuh-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = module.wazuh_vpc.vpc_id

  tags = {
    Name        = "${var.env_name}-wazuh-vpc-endpoints-sg"
    Group       = var.env_group
    Environment = var.env_name
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https_from_wazuh" {
  security_group_id = aws_security_group.vpc_endpoints.id
  description       = "HTTPS from Wazuh cluster"

  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.wazuh_cluster.id

  tags = {
    Name = "vpc-endpoints-https-from-wazuh"
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_https_from_bastion" {
  security_group_id = aws_security_group.vpc_endpoints.id
  description       = "HTTPS from bastion"

  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.bastion.id

  tags = {
    Name = "vpc-endpoints-https-from-bastion"
  }
}

# Security Group for Wazuh Cluster
resource "aws_security_group" "wazuh_cluster" {
  name        = "${var.env_name}-wazuh-cluster-sg"
  description = "Security group for Wazuh cluster communication"
  vpc_id      = module.wazuh_vpc.vpc_id

  tags = {
    Name        = "${var.env_name}-wazuh-cluster-sg"
    Group       = var.env_group
    Environment = var.env_name
    Purpose     = "Wazuh Cluster"
  }
}

# SSH from bastion
resource "aws_vpc_security_group_ingress_rule" "wazuh_ssh_from_bastion" {
  security_group_id = aws_security_group.wazuh_cluster.id
  description       = "SSH from bastion host"

  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.bastion.id

  tags = {
    Name = "ssh-from-bastion"
  }
}

# Wazuh Agent communication (1514) - events/data from agents
resource "aws_vpc_security_group_ingress_rule" "wazuh_agent_events" {
  security_group_id = aws_security_group.wazuh_cluster.id
  description       = "Wazuh agent event communication"

  from_port   = 1514
  to_port     = 1514
  ip_protocol = "tcp"
  cidr_ipv4   = "10.0.0.0/8"

  tags = {
    Name = "wazuh-agent-events"
  }
}

# Wazuh Agent registration (1515)
resource "aws_vpc_security_group_ingress_rule" "wazuh_agent_registration" {
  security_group_id = aws_security_group.wazuh_cluster.id
  description       = "Wazuh agent registration"

  from_port   = 1515
  to_port     = 1515
  ip_protocol = "tcp"
  cidr_ipv4   = "10.0.0.0/8"

  tags = {
    Name = "wazuh-agent-registration"
  }
}

# Wazuh Manager cluster communication (1516)
resource "aws_vpc_security_group_ingress_rule" "wazuh_cluster_comm" {
  security_group_id = aws_security_group.wazuh_cluster.id
  description       = "Wazuh cluster communication between manager nodes"

  from_port                    = 1516
  to_port                      = 1516
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.wazuh_cluster.id

  tags = {
    Name = "wazuh-cluster-comm"
  }
}

# Wazuh API (55000)
resource "aws_vpc_security_group_ingress_rule" "wazuh_api" {
  security_group_id = aws_security_group.wazuh_cluster.id
  description       = "Wazuh API access"

  from_port                    = 55000
  to_port                      = 55000
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.wazuh_cluster.id

  tags = {
    Name = "wazuh-api"
  }
}

# Wazuh Indexer REST API (9200)
resource "aws_vpc_security_group_ingress_rule" "wazuh_indexer_api" {
  security_group_id = aws_security_group.wazuh_cluster.id
  description       = "Wazuh indexer REST API communication"

  from_port                    = 9200
  to_port                      = 9200
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.wazuh_cluster.id

  tags = {
    Name = "wazuh-indexer-api"
  }
}

# Wazuh Indexer cluster communication (9300-9400)
resource "aws_vpc_security_group_ingress_rule" "wazuh_indexer_cluster" {
  security_group_id = aws_security_group.wazuh_cluster.id
  description       = "Wazuh indexer cluster communication"

  from_port                    = 9300
  to_port                      = 9400
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.wazuh_cluster.id

  tags = {
    Name = "wazuh-indexer-cluster"
  }
}

# Wazuh Dashboard (443)
resource "aws_vpc_security_group_ingress_rule" "wazuh_dashboard" {
  security_group_id = aws_security_group.wazuh_cluster.id
  description       = "Wazuh dashboard HTTPS access"

  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
  cidr_ipv4   = "10.0.0.0/8"

  tags = {
    Name = "wazuh-dashboard-https"
  }
}

# Allow all outbound traffic
resource "aws_vpc_security_group_egress_rule" "wazuh_outbound" {
  security_group_id = aws_security_group.wazuh_cluster.id
  description       = "Allow outbound traffic inside VPC"

  ip_protocol = "-1"
  cidr_ipv4   = "10.0.0.0/8"

  tags = {
    Name = "wazuh-outbound"
  }
}

# Bastion Host Security Group
resource "aws_security_group" "bastion" {
  name        = "${var.env_name}-wazuh-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = module.wazuh_vpc.vpc_id

  tags = {
    Name        = "${var.env_name}-wazuh-bastion-sg"
    Group       = var.env_group
    Environment = var.env_name
  }
}

# SSH access to bastion from trusted IPs
resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  security_group_id = aws_security_group.bastion.id
  description       = "SSH access from trusted IPs"

  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"
  cidr_ipv4   = var.trusted_ssh_cidr

  tags = {
    Name = "bastion-ssh"
  }
}

resource "aws_vpc_security_group_egress_rule" "bastion_outbound" {
  security_group_id = aws_security_group.bastion.id
  description       = "Allow outbound inside VPC"

  ip_protocol = "-1"
  cidr_ipv4   = "10.0.0.0/8"

  tags = {
    Name = "bastion-outbound"
  }
}

# Outputs
output "wazuh_vpc_id" {
  description = "Wazuh VPC ID"
  value       = module.wazuh_vpc.vpc_id
}

output "wazuh_vpc_cidr" {
  description = "Wazuh VPC CIDR block"
  value       = module.wazuh_vpc.vpc_cidr_block
}

output "wazuh_private_subnets" {
  description = "Wazuh private subnet IDs"
  value       = module.wazuh_vpc.private_subnets
}

output "wazuh_public_subnets" {
  description = "Wazuh public subnet IDs"
  value       = module.wazuh_vpc.public_subnets
}

output "wazuh_private_route_table_ids" {
  description = "Private route table IDs for VPC peering"
  value       = module.wazuh_vpc.private_route_table_ids
}
