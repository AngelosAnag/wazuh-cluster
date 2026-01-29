###############################################################################
# Terraform Backend Configuration
# Update the bucket name to your S3 bucket
###############################################################################

terraform {
  backend "s3" {
    bucket  = "angelos-test-terraform-state"
    key     = "wazuh/01-infrastructure/terraform.tfstate"
    region  = "eu-central-1"
    encrypt = true
  }
}
