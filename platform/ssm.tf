###############################################################################
# SSM Documents for Wazuh Installation
###############################################################################

# S3 Bucket for certificates
resource "aws_s3_bucket" "wazuh_artifacts" {
  bucket = "wazuh-${var.environment}-artifacts-${random_id.bucket_suffix.hex}"

  tags = {
    Name        = "wazuh-${var.environment}-artifacts"
    Environment = var.environment
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "wazuh_artifacts" {
  bucket = aws_s3_bucket.wazuh_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "wazuh_artifacts" {
  bucket = aws_s3_bucket.wazuh_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "wazuh_artifacts" {
  bucket = aws_s3_bucket.wazuh_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM policy for S3 access
resource "aws_iam_role_policy" "wazuh_s3_access" {
  name = "wazuh-${var.environment}-s3-access"
  role = aws_iam_role.wazuh_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.wazuh_artifacts.arn,
          "${aws_s3_bucket.wazuh_artifacts.arn}/*"
        ]
      }
    ]
  })
}

###############################################################################
# SSM Documents
###############################################################################

resource "aws_ssm_document" "generate_certificates" {
  name            = "Wazuh-GenerateCertificates-${var.environment}"
  document_type   = "Command"
  document_format = "YAML"

  content = templatefile("${path.module}/ssm-documents/01-generate-certificates.yaml", {})

  tags = {
    Name        = "Wazuh-GenerateCertificates"
    Environment = var.environment
  }
}

resource "aws_ssm_document" "distribute_certificates" {
  name            = "Wazuh-DistributeCertificates-${var.environment}"
  document_type   = "Command"
  document_format = "YAML"

  content = templatefile("${path.module}/ssm-documents/02-distribute-certificates.yaml", {})

  tags = {
    Name        = "Wazuh-DistributeCertificates"
    Environment = var.environment
  }
}

resource "aws_ssm_document" "install_indexer" {
  name            = "Wazuh-InstallIndexer-${var.environment}"
  document_type   = "Command"
  document_format = "YAML"

  content = templatefile("${path.module}/ssm-documents/03-install-indexer.yaml", {})

  tags = {
    Name        = "Wazuh-InstallIndexer"
    Environment = var.environment
  }
}

resource "aws_ssm_document" "initialize_indexer_cluster" {
  name            = "Wazuh-InitializeIndexerCluster-${var.environment}"
  document_type   = "Command"
  document_format = "YAML"

  content = templatefile("${path.module}/ssm-documents/04-initialize-indexer-cluster.yaml", {})

  tags = {
    Name        = "Wazuh-InitializeIndexerCluster"
    Environment = var.environment
  }
}

resource "aws_ssm_document" "install_manager" {
  name            = "Wazuh-InstallManager-${var.environment}"
  document_type   = "Command"
  document_format = "YAML"

  content = templatefile("${path.module}/ssm-documents/05-install-manager.yaml", {})

  tags = {
    Name        = "Wazuh-InstallManager"
    Environment = var.environment
  }
}

resource "aws_ssm_document" "install_dashboard" {
  name            = "Wazuh-InstallDashboard-${var.environment}"
  document_type   = "Command"
  document_format = "YAML"

  content = templatefile("${path.module}/ssm-documents/06-install-dashboard.yaml", {})

  tags = {
    Name        = "Wazuh-InstallDashboard"
    Environment = var.environment
  }
}
