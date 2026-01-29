###############################################################################
# Variables for 03-Wazuh-Install
###############################################################################

variable "aws_region" {
  description = "AWS region (must match previous layers)"
  type        = string
  default     = "eu-central-1"
}

variable "state_bucket" {
  description = "S3 bucket containing Terraform state"
  type        = string
  default     = "angelos-test-terraform-state"
}
