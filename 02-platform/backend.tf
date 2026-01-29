###############################################################################
# Terraform Backend Configuration
###############################################################################

terraform {
  backend "s3" {
    bucket  = "angelos-test-terraform-state"
    key     = "wazuh/02-platform/terraform.tfstate"
    region  = "eu-central-1"
    encrypt = true
  }
}
