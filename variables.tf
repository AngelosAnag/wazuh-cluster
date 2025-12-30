# =============================================================================
# Variables for Wazuh Cluster Infrastructure
# =============================================================================

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-west-1"
}

variable "env_name" {
  description = "Environment name prefix for resources"
  type        = string
  default     = "oktopay-pci"
}

variable "env_group" {
  description = "Environment group tag"
  type        = string
  default     = "wazuh-cluster"
}

# VPC Configuration
variable "wazuh_vpc_cidr" {
  description = "CIDR block for the Wazuh VPC"
  type        = string
  default     = "10.172.0.0/16"
}

variable "wazuh_private_subnets" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.172.11.0/24", "10.172.12.0/24"]
}

variable "wazuh_public_subnets" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.172.1.0/24", "10.172.2.0/24"]
}

# Security
variable "trusted_ssh_cidr" {
  description = "CIDR block allowed to SSH to bastion (your office/home IP)"
  type        = string
  # IMPORTANT: Change this to your actual IP
  # Example: "203.0.113.50/32"
}

variable "ssh_public_key_path" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/wazuh-cluster-key.pub"
}

# Alerting
variable "sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms (leave empty to create new)"
  type        = string
  default     = ""
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
