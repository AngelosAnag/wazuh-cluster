# 1. Generate Certificates (on node-1)
aws ssm send-command --document-name "Wazuh-GenerateCertificates-$ENV" \
  --targets "Key=instanceids,Values=$NODE1_ID" \
  --parameters "Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP,S3Bucket=$S3_BUCKET" \
  --region $REGION

# 2. Distribute Certificates (on all nodes)
aws ssm send-command --document-name "Wazuh-DistributeCertificates-$ENV" \
  --targets "Key=instanceids,Values=$NODE1_ID" \
  --parameters "S3Bucket=$S3_BUCKET,NodeName=node-1" \
  --region $REGION

aws ssm send-command --document-name "Wazuh-DistributeCertificates-$ENV" \
  --targets "Key=instanceids,Values=$NODE2_ID" \
  --parameters "S3Bucket=$S3_BUCKET,NodeName=node-2" \
  --region $REGION

aws ssm send-command --document-name "Wazuh-DistributeCertificates-$ENV" \
  --targets "Key=instanceids,Values=$NODE3_ID" \
  --parameters "S3Bucket=$S3_BUCKET,NodeName=node-3" \
  --region $REGION

# 3. Change permissions to wazuh-indexer user and group (on all nodes)
# SSH into each node after distributing:
sudo chown -R wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/certs/ 
sudo systemctl start wazuh-indexer

# 3. Install Indexer - one at a time
aws ssm send-command --document-name "Wazuh-InstallIndexer-$ENV" \
  --targets "Key=instanceids,Values=$NODE1_ID" \
  --parameters "NodeName=node-1,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP" \
  --region $REGION

aws ssm send-command --document-name "Wazuh-InstallIndexer-$ENV" \
  --targets "Key=instanceids,Values=$NODE2_ID" \
  --parameters "NodeName=node-2,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP" \
  --region $REGION

aws ssm send-command --document-name "Wazuh-InstallIndexer-$ENV" \
  --targets "Key=instanceids,Values=$NODE3_ID" \
  --parameters "NodeName=node-3,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP" \
  --region $REGION

############################

# 4. Initialize Indexer Cluster (on node-1)
aws ssm send-command --document-name "Wazuh-InitializeIndexerCluster-$ENV" \
  --targets "Key=instanceids,Values=$NODE1_ID" \
  --parameters "IndexerIP=$NODE1_IP" \
  --region $REGION

# Check: aws ssm list-commands --region $REGION --max-results 1

# 5. Install Manager Master (on node-1)
aws ssm send-command --document-name "Wazuh-InstallManager-$ENV" \
  --targets "Key=instanceids,Values=$NODE1_ID" \
  --parameters "NodeName=node-1,NodeType=master,MasterIP=$NODE1_IP,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP,ClusterKey=c98b62a9b6169ac5f67dae55ae4a9088" \
  --region $REGION

# Check: aws ssm list-commands --region $REGION --max-results 1

# 6. Install Manager Worker (on node-2)
aws ssm send-command --document-name "Wazuh-InstallManager-$ENV" \
  --targets "Key=instanceids,Values=$NODE2_ID" \
  --parameters "NodeName=node-2,NodeType=worker,MasterIP=$NODE1_IP,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP,ClusterKey=c98b62a9b6169ac5f67dae55ae4a9088" \
  --region $REGION

# Check: aws ssm list-commands --region $REGION --max-results 1

# 7. Install Dashboard (on node-3)
aws ssm send-command --document-name "Wazuh-InstallDashboard-$ENV" \
  --targets "Key=instanceids,Values=$NODE3_ID" \
  --parameters "DashboardIP=$NODE3_IP,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP,WazuhAPIIP=$NODE1_IP" \
  --region $REGION

# Check: aws ssm list-commands --region $REGION --max-results 1