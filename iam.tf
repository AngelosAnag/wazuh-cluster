# Data source for current AWS account (single definition)
data "aws_caller_identity" "current" {}

# IAM Role for EC2 instances
resource "aws_iam_role" "wazuh_ec2_role" {
  name        = "${var.env_name}-wazuh-ec2-role"
  description = "IAM role for Wazuh EC2 instances"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.env_name}-wazuh-ec2-role"
    Group       = var.env_group
    Environment = var.env_name
  }
}

# Attach SSM managed policy for Session Manager access
resource "aws_iam_role_policy_attachment" "wazuh_ssm_managed" {
  role       = aws_iam_role.wazuh_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Custom policy for CloudWatch monitoring
resource "aws_iam_policy" "wazuh_cloudwatch" {
  name        = "${var.env_name}-wazuh-cloudwatch-policy"
  description = "Policy for Wazuh instances to send metrics to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = ["CWAgent", "AWS/EC2", "Wazuh"]
          }
        }
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/wazuh/*",
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/wazuh/*:*"
        ]
      },
      {
        Sid    = "EC2DescribeTags"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes"
        ]
        Resource = "*"
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*"
        ]
        Resource = [
          aws_kms_key.wazuh_ebs.arn,
          aws_kms_key.wazuh_logs.arn
        ]
      }
    ]
  })

  tags = {
    Name        = "${var.env_name}-wazuh-cloudwatch-policy"
    Group       = var.env_group
    Environment = var.env_name
  }
}

resource "aws_iam_role_policy_attachment" "wazuh_cloudwatch" {
  role       = aws_iam_role.wazuh_ec2_role.name
  policy_arn = aws_iam_policy.wazuh_cloudwatch.arn
}

# Instance Profile
resource "aws_iam_instance_profile" "wazuh_profile" {
  name = "${var.env_name}-wazuh-profile"
  role = aws_iam_role.wazuh_ec2_role.name

  tags = {
    Name        = "${var.env_name}-wazuh-profile"
    Group       = var.env_group
    Environment = var.env_name
  }
}

# SSH Key Pair
# To create: ssh-keygen -t ed25519 -f ~/.ssh/wazuh-cluster-key -C "wazuh-cluster"
resource "aws_key_pair" "wazuh_cluster" {
  key_name   = "${var.env_name}-wazuh-cluster-key"
  public_key = file(var.ssh_public_key_path)

  tags = {
    Name        = "${var.env_name}-wazuh-cluster-key"
    Group       = var.env_group
    Environment = var.env_name
  }
}

# Outputs
output "wazuh_ec2_role_arn" {
  description = "ARN of the Wazuh EC2 IAM role"
  value       = aws_iam_role.wazuh_ec2_role.arn
}

output "wazuh_instance_profile_name" {
  description = "Name of the Wazuh instance profile"
  value       = aws_iam_instance_profile.wazuh_profile.name
}
