###############################################################################
# Variables for 02-Platform
###############################################################################

variable "aws_region" {
  description = "AWS region (must match 01-infrastructure)"
  type        = string
  default     = "eu-central-1"
}

variable "state_bucket" {
  description = "S3 bucket containing Terraform state"
  type        = string
  default     = "angelos-test-terraform-state"
}

variable "instance_type" {
  description = "EC2 instance type for Wazuh nodes"
  type        = string
  default     = "c5.large"
}

variable "ebs_volume_size" {
  description = "Size of EBS data volume in GB"
  type        = number
  default     = 300
}

variable "acm_certificate_arn" {
  description = "ARN of ACM certificate for HTTPS (optional)"
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS record"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for the Wazuh dashboard (must match ACM certificate)"
  type        = string
  default     = ""
}
