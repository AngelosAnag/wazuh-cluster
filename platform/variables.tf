###############################################################################
# Platform Module Variables
###############################################################################

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of private subnets"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "IDs of public subnets"
  type        = list(string)
}

variable "wazuh_node_sg_id" {
  description = "Security group ID for Wazuh nodes"
  type        = string
}

variable "alb_sg_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
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
  description = "ARN of ACM certificate for HTTPS on ALB (optional)"
  type        = string
  default     = ""
}

variable "ami_id" {
  description = "AMI ID for the EC2 instances"
  type        = string
  default     = "ami-01f79b1e4a5c64257" # Ubuntu Server 22.04 LTS in eu-central-1
}