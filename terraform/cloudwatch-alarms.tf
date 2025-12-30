# CloudWatch Log Group for Wazuh
resource "aws_cloudwatch_log_group" "wazuh" {
  count = terraform.workspace == "wazuh" ? 1 : 0

  name              = "/aws/wazuh/${var.env_name}"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.wazuh_logs.arn

  tags = {
    Name        = "${var.env_name}-wazuh-logs"
    Group       = var.env_group
    Environment = var.env_name
    Compliance  = "PCI-DSS"
  }
}

# SNS Topic for alerts (if not provided externally)
resource "aws_sns_topic" "wazuh_alerts" {
  count = terraform.workspace == "wazuh" && var.sns_topic_arn == "" ? 1 : 0

  name              = "${var.env_name}-wazuh-alerts"
  kms_master_key_id = aws_kms_key.wazuh_logs.id

  tags = {
    Name        = "${var.env_name}-wazuh-alerts"
    Group       = var.env_group
    Environment = var.env_name
  }
}

locals {
  # Use provided SNS topic or create one
  alarm_sns_topic_arn = var.sns_topic_arn != "" ? var.sns_topic_arn : try(aws_sns_topic.wazuh_alerts[0].arn, "")
}

# CloudWatch alarms for indexer nodes - CPU
resource "aws_cloudwatch_metric_alarm" "wazuh_indexer_cpu" {
  for_each = { for k, v in local.wazuh_nodes : k => v if v.node_type == "indexer" }

  alarm_name          = "${var.env_name}-wazuh-${each.key}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alert when CPU exceeds 80% for indexer node ${each.key}"
  alarm_actions       = local.alarm_sns_topic_arn != "" ? [local.alarm_sns_topic_arn] : []
  ok_actions          = local.alarm_sns_topic_arn != "" ? [local.alarm_sns_topic_arn] : []

  dimensions = {
    InstanceId = aws_instance.wazuh_server_ec2[each.key].id
  }

  tags = {
    Name        = "${var.env_name}-wazuh-${each.key}-cpu-alarm"
    Group       = var.env_group
    Environment = var.env_name
  }
}

# CloudWatch alarms for master/worker nodes - CPU
resource "aws_cloudwatch_metric_alarm" "wazuh_manager_cpu" {
  for_each = { for k, v in local.wazuh_nodes : k => v if v.node_type == "master" || v.node_type == "worker" }

  alarm_name          = "${var.env_name}-wazuh-${each.key}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "Alert when CPU exceeds 75% for manager node ${each.key}"
  alarm_actions       = local.alarm_sns_topic_arn != "" ? [local.alarm_sns_topic_arn] : []
  ok_actions          = local.alarm_sns_topic_arn != "" ? [local.alarm_sns_topic_arn] : []

  dimensions = {
    InstanceId = aws_instance.wazuh_server_ec2[each.key].id
  }

  tags = {
    Name        = "${var.env_name}-wazuh-${each.key}-cpu-alarm"
    Group       = var.env_group
    Environment = var.env_name
  }
}

# CloudWatch alarms for disk space (requires CloudWatch Agent)
resource "aws_cloudwatch_metric_alarm" "wazuh_disk_space" {
  for_each = local.wazuh_nodes

  alarm_name          = "${var.env_name}-wazuh-${each.key}-disk-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alert when disk usage exceeds 80% on ${each.key}"
  alarm_actions       = local.alarm_sns_topic_arn != "" ? [local.alarm_sns_topic_arn] : []
  ok_actions          = local.alarm_sns_topic_arn != "" ? [local.alarm_sns_topic_arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.wazuh_server_ec2[each.key].id
    path       = "/"
    fstype     = "xfs"
  }

  tags = {
    Name        = "${var.env_name}-wazuh-${each.key}-disk-alarm"
    Group       = var.env_group
    Environment = var.env_name
  }
}

# Memory alarm (requires CloudWatch Agent)
resource "aws_cloudwatch_metric_alarm" "wazuh_memory" {
  for_each = local.wazuh_nodes

  alarm_name          = "${var.env_name}-wazuh-${each.key}-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "mem_used_percent"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "Alert when memory usage exceeds 85% on ${each.key}"
  alarm_actions       = local.alarm_sns_topic_arn != "" ? [local.alarm_sns_topic_arn] : []
  ok_actions          = local.alarm_sns_topic_arn != "" ? [local.alarm_sns_topic_arn] : []
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = aws_instance.wazuh_server_ec2[each.key].id
  }

  tags = {
    Name        = "${var.env_name}-wazuh-${each.key}-memory-alarm"
    Group       = var.env_group
    Environment = var.env_name
  }
}

# Instance status check alarm
resource "aws_cloudwatch_metric_alarm" "wazuh_status_check" {
  for_each = local.wazuh_nodes

  alarm_name          = "${var.env_name}-wazuh-${each.key}-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Alert when status check fails on ${each.key}"
  alarm_actions       = local.alarm_sns_topic_arn != "" ? [local.alarm_sns_topic_arn] : []

  dimensions = {
    InstanceId = aws_instance.wazuh_server_ec2[each.key].id
  }

  tags = {
    Name        = "${var.env_name}-wazuh-${each.key}-status-alarm"
    Group       = var.env_group
    Environment = var.env_name
  }
}

# Outputs
output "wazuh_log_group_name" {
  description = "CloudWatch Log Group name for Wazuh"
  value       = try(aws_cloudwatch_log_group.wazuh[0].name, null)
}

output "wazuh_alerts_topic_arn" {
  description = "SNS topic ARN for Wazuh alerts"
  value       = local.alarm_sns_topic_arn
}
