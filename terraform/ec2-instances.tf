# Wazuh node definitions with subnet assignments
locals {
  wazuh_nodes = terraform.workspace == "wazuh" ? {
    indexer-1 = {
      instance_type = "t3.small"
      private_ip    = "10.172.11.7"
      az            = "${var.aws_region}a"
      subnet_id     = module.wazuh_vpc.private_subnets[0]
      volume_size   = 50
      node_type     = "indexer"
    }
    indexer-2 = {
      instance_type = "t3.small"
      private_ip    = "10.172.11.8"
      az            = "${var.aws_region}b"
      subnet_id     = module.wazuh_vpc.private_subnets[1]
      volume_size   = 50
      node_type     = "indexer"
    }
    master = {
      instance_type = "t3.medium"
      private_ip    = "10.172.11.9"
      az            = "${var.aws_region}a"
      subnet_id     = module.wazuh_vpc.private_subnets[0]
      volume_size   = 100
      node_type     = "master"
    }
    worker-1 = {
      instance_type = "t3.small"
      private_ip    = "10.172.11.10"
      az            = "${var.aws_region}a"
      subnet_id     = module.wazuh_vpc.private_subnets[0]
      volume_size   = 75
      node_type     = "worker"
    }
    worker-2 = {
      instance_type = "t3.small"
      private_ip    = "10.172.11.11"
      az            = "${var.aws_region}b"
      subnet_id     = module.wazuh_vpc.private_subnets[1]
      volume_size   = 75
      node_type     = "worker"
    }
  } : {}
}

# Wazuh cluster EC2 instances
resource "aws_instance" "wazuh_server_ec2" {
  for_each = local.wazuh_nodes

  ami                         = data.aws_ami.amazon_linux_2023.id
  associate_public_ip_address = false
  availability_zone           = each.value.az
  disable_api_stop            = false
  disable_api_termination     = true
  ebs_optimized               = true
  get_password_data           = false
  hibernation                 = false
  iam_instance_profile        = aws_iam_instance_profile.wazuh_profile.name
  instance_type               = each.value.instance_type
  key_name                    = aws_key_pair.wazuh_cluster.key_name
  monitoring                  = true

  instance_initiated_shutdown_behavior = "stop"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  private_ip        = each.value.private_ip
  source_dest_check = true
  subnet_id         = each.value.subnet_id

  vpc_security_group_ids = [aws_security_group.wazuh_cluster.id]

  user_data_replace_on_change = false

  tags = {
    Name     = "${var.env_name}-wazuh-${each.key}"
    Group    = var.env_group
    NodeType = each.value.node_type
    Role     = each.value.node_type
    Backup   = "daily"
  }

  tenancy = "default"

  capacity_reservation_specification {
    capacity_reservation_preference = "open"
  }

  enclave_options {
    enabled = false
  }

  maintenance_options {
    auto_recovery = "default"
  }

  root_block_device {
    delete_on_termination = true
    encrypted             = true
    kms_key_id            = aws_kms_key.wazuh_ebs.arn
    iops                  = 3000
    throughput            = 125
    volume_size           = each.value.volume_size
    volume_type           = "gp3"

    tags = {
      Name      = "${var.env_name}-wazuh-${each.key}-root"
      NodeType  = each.value.node_type
      Encrypted = "true"
    }
  }

  lifecycle {
    ignore_changes  = [ami]
    prevent_destroy = false
  }

  depends_on = [
    module.wazuh_vpc,
    aws_kms_key.wazuh_ebs,
    aws_security_group.wazuh_cluster
  ]
}

# AMI data source for Amazon Linux 2023
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Bastion Host (small instance in public subnet)
resource "aws_instance" "bastion" {
  count = terraform.workspace == "wazuh" ? 1 : 0

  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro"
  key_name                    = aws_key_pair.wazuh_cluster.key_name
  subnet_id                   = module.wazuh_vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.wazuh_profile.name

  monitoring              = true
  disable_api_termination = false
  disable_api_stop        = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    kms_key_id            = aws_kms_key.wazuh_ebs.arn
    delete_on_termination = true
  }

  tags = {
    Name        = "${var.env_name}-wazuh-bastion"
    Group       = var.env_group
    Environment = var.env_name
    Role        = "bastion"
  }

  depends_on = [
    module.wazuh_vpc,
    aws_kms_key.wazuh_ebs
  ]
}

# Outputs
output "bastion_public_ip" {
  description = "Bastion host public IP"
  value       = try(aws_instance.bastion[0].public_ip, null)
}

output "bastion_ssh_command" {
  description = "SSH command to connect to bastion"
  value       = try("ssh -i ~/.ssh/wazuh-cluster-key ec2-user@${aws_instance.bastion[0].public_ip}", null)
}

output "wazuh_nodes" {
  description = "Wazuh cluster node details"
  value = {
    for k, v in aws_instance.wazuh_server_ec2 : k => {
      instance_id = v.id
      private_ip  = v.private_ip
      node_type   = v.tags["NodeType"]
      az          = v.availability_zone
    }
  }
}

output "wazuh_indexer_ips" {
  description = "Indexer node IPs for configuration"
  value = [
    for k, v in aws_instance.wazuh_server_ec2 : v.private_ip
    if v.tags["NodeType"] == "indexer"
  ]
}

output "wazuh_master_ip" {
  description = "Master node IP for agent configuration"
  value = [
    for k, v in aws_instance.wazuh_server_ec2 : v.private_ip
    if v.tags["NodeType"] == "master"
  ][0]
}

output "wazuh_worker_ips" {
  description = "Worker node IPs for agent configuration"
  value = [
    for k, v in aws_instance.wazuh_server_ec2 : v.private_ip
    if v.tags["NodeType"] == "worker"
  ]
}

output "wazuh_nodes_ssh_info" {
  description = "SSH connection info for Wazuh nodes via bastion"
  value = {
    for k, v in aws_instance.wazuh_server_ec2 : k => {
      private_ip  = v.private_ip
      ssh_command = "ssh -i ~/.ssh/wazuh-cluster-key -J ec2-user@${try(aws_instance.bastion[0].public_ip, "BASTION_IP")} ec2-user@${v.private_ip}"
      node_type   = v.tags["NodeType"]
    }
  }
}
