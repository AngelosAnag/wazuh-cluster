# KMS key for Wazuh EBS volumes
resource "aws_kms_key" "wazuh_ebs" {
  description              = "KMS key for Wazuh cluster EBS volume encryption"
  deletion_window_in_days  = 30
  enable_key_rotation      = true
  multi_region             = false
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  key_usage                = "ENCRYPT_DECRYPT"

  tags = {
    Name        = "${var.env_name}-wazuh-ebs-kms"
    Group       = var.env_group
    Purpose     = "EBS Encryption"
    Compliance  = "PCI-DSS"
    Environment = var.env_name
  }
}

# KMS key alias for easier reference
resource "aws_kms_alias" "wazuh_ebs" {
  name          = "alias/${var.env_name}-wazuh-ebs"
  target_key_id = aws_kms_key.wazuh_ebs.key_id
}

# KMS key policy - simplified to avoid circular dependencies
resource "aws_kms_key_policy" "wazuh_ebs" {
  key_id = aws_kms_key.wazuh_ebs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowEC2ToUseKey"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ec2.${var.aws_region}.amazonaws.com"
          }
        }
      },
      {
        Sid    = "AllowEBSServiceToUseKey"
        Effect = "Allow"
        Principal = {
          Service = "ebs.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:GenerateDataKey",
          "kms:GenerateDataKeyWithoutPlaintext"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowAutoscalingService"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      },
      {
        Sid    = "AllowWazuhEC2Role"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.wazuh_ec2_role.arn
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*"
        ]
        Resource = "*"
      }
    ]
  })

  depends_on = [aws_iam_role.wazuh_ec2_role]
}

# KMS key for CloudWatch Logs
resource "aws_kms_key" "wazuh_logs" {
  description              = "KMS key for Wazuh CloudWatch Logs encryption"
  deletion_window_in_days  = 30
  enable_key_rotation      = true
  multi_region             = false
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  key_usage                = "ENCRYPT_DECRYPT"

  tags = {
    Name        = "${var.env_name}-wazuh-logs-kms"
    Group       = var.env_group
    Purpose     = "CloudWatch Logs Encryption"
    Compliance  = "PCI-DSS"
    Environment = var.env_name
  }
}

resource "aws_kms_alias" "wazuh_logs" {
  name          = "alias/${var.env_name}-wazuh-logs"
  target_key_id = aws_kms_key.wazuh_logs.key_id
}

# KMS key policy for CloudWatch Logs
resource "aws_kms_key_policy" "wazuh_logs" {
  key_id = aws_kms_key.wazuh_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:CreateGrant",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },
      {
        Sid    = "AllowVPCFlowLogs"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

# Outputs
output "wazuh_ebs_kms_key_id" {
  description = "KMS key ID for Wazuh EBS encryption"
  value       = aws_kms_key.wazuh_ebs.id
}

output "wazuh_ebs_kms_key_arn" {
  description = "KMS key ARN for Wazuh EBS encryption"
  value       = aws_kms_key.wazuh_ebs.arn
}

output "wazuh_logs_kms_key_id" {
  description = "KMS key ID for Wazuh CloudWatch Logs encryption"
  value       = aws_kms_key.wazuh_logs.id
}

output "wazuh_logs_kms_key_arn" {
  description = "KMS key ARN for Wazuh CloudWatch Logs encryption"
  value       = aws_kms_key.wazuh_logs.arn
}
