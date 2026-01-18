
###############################################################################
# Network Load Balancer (for Agent Registration)
###############################################################################

resource "aws_lb" "nlb" {
  name               = "wazuh-${var.environment}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = var.private_subnet_ids

  enable_cross_zone_load_balancing = true

  tags = {
    Name        = "wazuh-${var.environment}-nlb"
    Environment = var.environment
  }
}

# Target Group for Agent Registration (1514)
resource "aws_lb_target_group" "agent_registration" {
  name        = "wazuh-${var.environment}-agent-reg"
  port        = 1514
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = 1515
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = {
    Name        = "wazuh-${var.environment}-agent-registration"
    Environment = var.environment
  }
}

# Target Group for Agent Events (1515)
resource "aws_lb_target_group" "agent_events" {
  name        = "wazuh-${var.environment}-agent-events"
  port        = 1515
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = 1515
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = {
    Name        = "wazuh-${var.environment}-agent-events"
    Environment = var.environment
  }
}

# NLB Listeners
resource "aws_lb_listener" "agent_registration" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 1514
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agent_registration.arn
  }
}

resource "aws_lb_listener" "agent_events" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 1515
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agent_events.arn
  }
}

# Attach Manager Nodes (node-1 and node-2) to NLB Target Groups
resource "aws_lb_target_group_attachment" "agent_registration" {
  for_each = {
    for k, v in local.wazuh_nodes : k => v if v.manager_enabled
  }

  target_group_arn = aws_lb_target_group.agent_registration.arn
  target_id        = module.wazuh_nodes[each.key].id
  port             = 1514
}

resource "aws_lb_target_group_attachment" "agent_events" {
  for_each = {
    for k, v in local.wazuh_nodes : k => v if v.manager_enabled
  }

  target_group_arn = aws_lb_target_group.agent_events.arn
  target_id        = module.wazuh_nodes[each.key].id
  port             = 1515
}
