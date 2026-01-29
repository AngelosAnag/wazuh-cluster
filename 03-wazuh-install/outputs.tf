###############################################################################
# Outputs for 03-Wazuh-Install
###############################################################################

output "ssm_documents" {
  description = "SSM document names"
  value = {
    generate_certificates      = aws_ssm_document.generate_certificates.name
    distribute_certificates    = aws_ssm_document.distribute_certificates.name
    install_indexer            = aws_ssm_document.install_indexer.name
    initialize_indexer_cluster = aws_ssm_document.initialize_indexer_cluster.name
    install_manager            = aws_ssm_document.install_manager.name
    install_dashboard          = aws_ssm_document.install_dashboard.name
  }
}

output "cluster_key" {
  description = "Wazuh manager cluster key"
  value       = random_password.cluster_key.result
  sensitive   = true
}

output "dashboard_url" {
  description = "Wazuh Dashboard URL"
  value       = local.platform.dashboard_url
}

output "nlb_dns_name" {
  description = "NLB DNS for agent registration"
  value       = local.platform.nlb_dns_name
}

output "installation_info" {
  description = "Information needed for manual SSM installation"
  value = {
    node1_id  = local.platform.node1_id
    node2_id  = local.platform.node2_id
    node3_id  = local.platform.node3_id
    node1_ip  = local.platform.node1_ip
    node2_ip  = local.platform.node2_ip
    node3_ip  = local.platform.node3_ip
    s3_bucket = local.platform.s3_artifacts_bucket
    region    = local.platform.aws_region
    env       = local.env
  }
}
