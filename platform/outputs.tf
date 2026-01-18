###############################################################################
# Platform Module Outputs
###############################################################################

output "wazuh_node_ids" {
  description = "Instance IDs of Wazuh nodes"
  value = {
    for k, v in module.wazuh_nodes : k => v.id
  }
}

output "wazuh_node_private_ips" {
  description = "Private IPs of Wazuh nodes"
  value = {
    for k, v in module.wazuh_nodes : k => v.private_ip
  }
}

output "wazuh_node_private_dns" {
  description = "Private DNS names of Wazuh nodes"
  value = {
    for k, v in module.wazuh_nodes : k => v.private_dns
  }
}

output "nlb_dns_name" {
  description = "DNS name of the NLB for agent registration"
  value       = aws_lb.nlb.dns_name
}

output "nlb_arn" {
  description = "ARN of the NLB"
  value       = aws_lb.nlb.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB for dashboard access"
  value       = aws_lb.alb.dns_name
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.alb.arn
}

output "ssh_connection_info" {
  description = "SSH connection info for each node"
  value = {
    for k, v in module.wazuh_nodes : k => {
      ssm_command = "aws ssm start-session --target ${v.id} --region ${data.aws_region.current.name}"
      private_ip  = v.private_ip
      role        = local.wazuh_nodes[k].role
    }
  }
}

output "wazuh_config_summary" {
  description = "Summary of Wazuh node configuration for config.yml"
  value       = <<-EOT
    
    ===== WAZUH CONFIG.YML TEMPLATE =====
    
    Use these IPs when generating certificates:
    
    nodes:
      indexer:
        - name: node-1
          ip: "${module.wazuh_nodes["node-1"].private_ip}"
        - name: node-2
          ip: "${module.wazuh_nodes["node-2"].private_ip}"
        - name: node-3
          ip: "${module.wazuh_nodes["node-3"].private_ip}"
    
      server:
        - name: wazuh-1
          ip: "${module.wazuh_nodes["node-1"].private_ip}"
          node_type: master
        - name: wazuh-2
          ip: "${module.wazuh_nodes["node-2"].private_ip}"
          node_type: worker
    
      dashboard:
        - name: dashboard
          ip: "${module.wazuh_nodes["node-3"].private_ip}"
    
    ===== NLB DNS (for agent registration) =====
    ${aws_lb.nlb.dns_name}
    
    ===== ALB DNS (for dashboard) =====
    ${aws_lb.alb.dns_name}
    
  EOT
}

###############################################################################
# SSM Document Outputs
###############################################################################

output "s3_artifacts_bucket" {
  description = "S3 bucket for Wazuh certificates and artifacts"
  value       = aws_s3_bucket.wazuh_artifacts.bucket
}

output "ssm_documents" {
  description = "SSM document names for Wazuh installation"
  value = {
    generate_certificates      = aws_ssm_document.generate_certificates.name
    distribute_certificates    = aws_ssm_document.distribute_certificates.name
    install_indexer            = aws_ssm_document.install_indexer.name
    initialize_indexer_cluster = aws_ssm_document.initialize_indexer_cluster.name
    install_manager            = aws_ssm_document.install_manager.name
    install_dashboard          = aws_ssm_document.install_dashboard.name
  }
}

output "installation_commands" {
  description = "AWS CLI commands to run SSM documents in order"
  value       = <<-EOT
    
    ===== WAZUH INSTALLATION STEPS =====
    
    Run these commands in order after 'terraform apply':
    
    # Set variables
    NODE1_ID="${module.wazuh_nodes["node-1"].id}"
    NODE2_ID="${module.wazuh_nodes["node-2"].id}"
    NODE3_ID="${module.wazuh_nodes["node-3"].id}"
    NODE1_IP="${module.wazuh_nodes["node-1"].private_ip}"
    NODE2_IP="${module.wazuh_nodes["node-2"].private_ip}"
    NODE3_IP="${module.wazuh_nodes["node-3"].private_ip}"
    S3_BUCKET="${aws_s3_bucket.wazuh_artifacts.bucket}"
    REGION="${data.aws_region.current.name}"
    ENV="${var.environment}"
    
    # Step 1: Generate certificates (on node-1)
    aws ssm send-command \
      --document-name "Wazuh-GenerateCertificates-$ENV" \
      --targets "Key=instanceids,Values=$NODE1_ID" \
      --parameters "Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP,S3Bucket=$S3_BUCKET" \
      --region $REGION
    
    # Step 2: Distribute certificates (on all nodes)
    for NODE in "node-1:$NODE1_ID" "node-2:$NODE2_ID" "node-3:$NODE3_ID"; do
      NAME=$(echo $NODE | cut -d: -f1)
      ID=$(echo $NODE | cut -d: -f2)
      aws ssm send-command \
        --document-name "Wazuh-DistributeCertificates-$ENV" \
        --targets "Key=instanceids,Values=$ID" \
        --parameters "S3Bucket=$S3_BUCKET,NodeName=$NAME" \
        --region $REGION
    done
    
    # Step 3: Install Indexer (on all nodes - can run in parallel)
    for NODE in "node-1:$NODE1_ID" "node-2:$NODE2_ID" "node-3:$NODE3_ID"; do
      NAME=$(echo $NODE | cut -d: -f1)
      ID=$(echo $NODE | cut -d: -f2)
      aws ssm send-command \
        --document-name "Wazuh-InstallIndexer-$ENV" \
        --targets "Key=instanceids,Values=$ID" \
        --parameters "NodeName=$NAME,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP" \
        --region $REGION
    done
    
    # Step 4: Initialize Indexer Cluster (once, on node-1)
    aws ssm send-command \
      --document-name "Wazuh-InitializeIndexerCluster-$ENV" \
      --targets "Key=instanceids,Values=$NODE1_ID" \
      --parameters "IndexerIP=$NODE1_IP" \
      --region $REGION
    
    # Step 5: Install Manager (on node-1 as master, node-2 as worker)
    aws ssm send-command \
      --document-name "Wazuh-InstallManager-$ENV" \
      --targets "Key=instanceids,Values=$NODE1_ID" \
      --parameters "NodeName=node-1,NodeType=master,MasterIP=$NODE1_IP,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP" \
      --region $REGION
    
    aws ssm send-command \
      --document-name "Wazuh-InstallManager-$ENV" \
      --targets "Key=instanceids,Values=$NODE2_ID" \
      --parameters "NodeName=node-2,NodeType=worker,MasterIP=$NODE1_IP,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP" \
      --region $REGION
    
    # Step 6: Install Dashboard (on node-3)
    aws ssm send-command \
      --document-name "Wazuh-InstallDashboard-$ENV" \
      --targets "Key=instanceids,Values=$NODE3_ID" \
      --parameters "DashboardIP=$NODE3_IP,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP,WazuhAPIIP=$NODE1_IP" \
      --region $REGION
    
    # Check command status
    aws ssm list-commands --region $REGION --max-results 10
    
  EOT
}
