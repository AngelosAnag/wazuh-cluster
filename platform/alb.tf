
###############################################################################
# Application Load Balancer (for Dashboard)
###############################################################################

resource "aws_lb" "alb" {
  name               = "wazuh-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false  # Set to true for production

  tags = {
    Name        = "wazuh-${var.environment}-alb"
    Environment = var.environment
  }
}

# Target Group for Dashboard
resource "aws_lb_target_group" "dashboard" {
  name        = "wazuh-${var.environment}-dashboard"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    protocol            = "HTTPS"
    port                = 443
    path                = "/api/status"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }

  tags = {
    Name        = "wazuh-${var.environment}-dashboard"
    Environment = var.environment
  }
}

# ALB Listener (HTTPS)
# Note: You'll need to provide a valid ACM certificate ARN
resource "aws_lb_listener" "dashboard_https" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dashboard.arn
  }

  # Only create if certificate is provided
  count = var.acm_certificate_arn != "" ? 1 : 0
}

# HTTP to HTTPS redirect (if certificate provided)
resource "aws_lb_listener" "dashboard_http_redirect" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  count = var.acm_certificate_arn != "" ? 1 : 0
}

# Attach Dashboard Node (node-3) to ALB Target Group
resource "aws_lb_target_group_attachment" "dashboard" {
  target_group_arn = aws_lb_target_group.dashboard.arn
  target_id        = module.wazuh_nodes["node-3"].id
  port             = 443
}
