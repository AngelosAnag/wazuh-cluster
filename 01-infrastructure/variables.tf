###############################################################################
# Variables for 01-Infrastructure
###############################################################################

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (e.g., prod, staging, playground)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the Wazuh Dashboard (your office/VPN IPs)"
  type        = list(string)
  default     = ["94.63.96.238/32"]
}
