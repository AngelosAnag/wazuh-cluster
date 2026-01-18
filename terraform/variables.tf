###############################################################################
# Root Variables
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (e.g., prod, staging, dev)"
  type        = string
  default     = "playground"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access the Wazuh dashboard (your office IPs, VPN, etc.)"
  type        = list(string)
  default     = [] # IPs added in tfvars
}

variable "instance_type" {
  description = "EC2 instance type for Wazuh nodes"
  type        = string
  default     = "m5.xlarge"
}

variable "key_name" {
  description = "Name of the SSH key pair (optional - leave empty if using SSM only)"
  type        = string
  default     = ""
}

variable "ebs_volume_size" {
  description = "Size of EBS data volume in GB"
  type        = number
  default     = 300
}

variable "acm_certificate_arn" {
  description = "ARN of ACM certificate for HTTPS on ALB (optional, leave empty for HTTP only)"
  type        = string
  default     = ""
}
