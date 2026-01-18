
###############################################################################
# Security Group for VPC Endpoints
###############################################################################

resource "aws_security_group" "vpc_endpoints" {
  name        = "wazuh-${var.environment}-vpc-endpoints-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wazuh-${var.environment}-vpc-endpoints-sg"
    Environment = var.environment
  }
}

###############################################################################
# Security Group - Wazuh Nodes
###############################################################################

resource "aws_security_group" "wazuh_nodes" {
  name        = "wazuh-${var.environment}-nodes-sg"
  description = "Security group for Wazuh cluster nodes"
  vpc_id      = module.vpc.vpc_id

  # Agent registration (from NLB - agents connect here)
  ingress {
    description = "Wazuh agent registration"
    from_port   = 1514
    to_port     = 1514
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Wazuh agent events"
    from_port   = 1515
    to_port     = 1515
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # Manager cluster sync
  ingress {
    description = "Wazuh manager cluster"
    from_port   = 1516
    to_port     = 1516
    protocol    = "tcp"
    self        = true
  }

  # Indexer REST API
  ingress {
    description = "Wazuh indexer REST API"
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    self        = true
  }

  # Indexer cluster communication
  ingress {
    description = "Wazuh indexer cluster"
    from_port   = 9300
    to_port     = 9300
    protocol    = "tcp"
    self        = true
  }

  # Wazuh API
  ingress {
    description = "Wazuh API"
    from_port   = 55000
    to_port     = 55000
    protocol    = "tcp"
    self        = true
  }

  # Dashboard (from ALB)
  ingress {
    description     = "Wazuh Dashboard from ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Wazuh Dashboard alt port from ALB"
    from_port       = 5601
    to_port         = 5601
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wazuh-${var.environment}-nodes-sg"
    Environment = var.environment
  }
}

###############################################################################
# Security Group - ALB (Dashboard access)
###############################################################################

resource "aws_security_group" "alb" {
  name        = "wazuh-${var.environment}-alb-sg"
  description = "Security group for Wazuh Dashboard ALB"
  vpc_id      = module.vpc.vpc_id

  # HTTPS from allowed IPs
  ingress {
    description = "HTTPS from allowed IPs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "wazuh-${var.environment}-alb-sg"
    Environment = var.environment
  }
}

###############################################################################
# Security Group - NLB (Agent registration)
# Note: NLB doesn't use security groups, but we create one for target health checks
###############################################################################

resource "aws_security_group" "nlb_targets" {
  name        = "wazuh-${var.environment}-nlb-targets-sg"
  description = "Allow NLB health checks to Wazuh managers"
  vpc_id      = module.vpc.vpc_id

  # Health check from NLB (NLB preserves client IP, so we allow VPC CIDR)
  ingress {
    description = "NLB health check"
    from_port   = 1515
    to_port     = 1515
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name        = "wazuh-${var.environment}-nlb-targets-sg"
    Environment = var.environment
  }
}
