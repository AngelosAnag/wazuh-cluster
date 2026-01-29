# Wazuh 3-Node Cluster Deployment Guide

This guide documents the complete process to deploy a Wazuh 3-node cluster on AWS.

## Architecture Overview

```
                           Internet
                               │
                               ▼
                    ┌─────────────────────┐
                    │  Application Load   │
                    │  Balancer (HTTPS)   │
                    │  Port 443 + ACM Cert│
                    └─────────────────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
              ▼                ▼                ▼
    ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
    │     Node-1      │ │     Node-2      │ │     Node-3      │
    │  Manager Master │ │  Manager Worker │ │   Dashboard     │
    │  + Indexer      │ │  + Indexer      │ │  + Indexer      │
    │  10.0.0.60      │ │  10.0.1.57      │ │  10.0.2.47      │
    └─────────────────┘ └─────────────────┘ └─────────────────┘
```

### Components per Node

| Node | Components | Purpose |
|------|------------|---------|
| node-1 | Wazuh Manager (master), Wazuh Indexer, Filebeat | Central management, event processing |
| node-2 | Wazuh Manager (worker), Wazuh Indexer, Filebeat | Distributed agent handling |
| node-3 | Wazuh Indexer, Wazuh Dashboard | Data storage and visualization |

## Prerequisites

### AWS Resources Required

1. **ACM Certificate**: A valid SSL certificate for HTTPS on the ALB
2. **S3 Bucket**: For Terraform state storage
3. **VPC**: With public and private subnets across 3 AZs
4. **IAM Permissions**: Administrator access or equivalent

### Local Requirements

- AWS CLI v2 configured with appropriate profile
- Terraform >= 1.7.0
- Bash shell

## Deployment Steps

### Step 1: Configure AWS Profile

```bash
export AWS_PROFILE=playground  # or your profile name
export AWS_REGION=eu-central-1

# Verify credentials
aws sts get-caller-identity
```

### Step 2: Create ACM Certificate (if needed)

```bash
# Request a certificate in ACM console or via CLI
aws acm request-certificate \
  --domain-name your-domain.example.com \
  --validation-method DNS \
  --region eu-central-1
```

Wait for certificate validation to complete.

### Step 3: Deploy Infrastructure (01-infrastructure)

```bash
cd wazuh-cluster/01-infrastructure

# Update terraform.tfvars if needed
# - aws_region
# - environment
# - allowed_cidr_blocks (for dashboard access)

terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

### Step 4: Deploy Platform (02-platform)

```bash
cd ../02-platform

# Update terraform.tfvars with:
# - acm_certificate_arn (YOUR ACM CERTIFICATE ARN)
# - instance_type (default: c5.large)
# - ebs_volume_size (default: 300GB)

terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Note the outputs:
- `node1_id`, `node2_id`, `node3_id`
- `node1_ip`, `node2_ip`, `node3_ip`
- `s3_artifacts_bucket`
- `dashboard_url`

### Step 5: Deploy SSM Documents (03-wazuh-install)

```bash
cd ../03-wazuh-install

terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

### Step 6: Run Wazuh Installation

You can use the automated script or manual commands.

#### Option A: Automated Script

```bash
cd ..
./install-wazuh.sh
```

#### Option B: Manual SSM Commands

Set environment variables:
```bash
export REGION=eu-central-1
export ENV=playground
export NODE1_ID=i-0f463b124fa192084 # The id that the first node receives and so on
export NODE2_ID=i-0eca2c12bc23b0e29
export NODE3_ID=i-06a1b316bd4141864
export NODE1_IP=10.0.0.60
export NODE2_IP=10.0.1.57
export NODE3_IP=10.0.2.47
export S3_BUCKET=wazuh-playground-artifacts-01e51fce
export CLUSTER_KEY=$(openssl rand -hex 16)
```

Run commands in sequence:

```bash
# 1. Generate Certificates (on node-1)
aws ssm send-command \
  --document-name "Wazuh-GenerateCertificates-$ENV" \
  --targets "Key=instanceids,Values=$NODE1_ID" \
  --parameters "Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP,S3Bucket=$S3_BUCKET" \
  --region $REGION

# Wait for completion, then...

# 2. Distribute Certificates (on all nodes)
aws ssm send-command \
  --document-name "Wazuh-DistributeCertificates-$ENV" \
  --targets "Key=instanceids,Values=$NODE1_ID" \
  --parameters "S3Bucket=$S3_BUCKET,NodeName=node-1" \
  --region $REGION

aws ssm send-command \
  --document-name "Wazuh-DistributeCertificates-$ENV" \
  --targets "Key=instanceids,Values=$NODE2_ID" \
  --parameters "S3Bucket=$S3_BUCKET,NodeName=node-2" \
  --region $REGION

aws ssm send-command \
  --document-name "Wazuh-DistributeCertificates-$ENV" \
  --targets "Key=instanceids,Values=$NODE3_ID" \
  --parameters "S3Bucket=$S3_BUCKET,NodeName=node-3" \
  --region $REGION

# 3. Install Indexer (on all nodes, one at a time)
aws ssm send-command \
  --document-name "Wazuh-InstallIndexer-$ENV" \
  --targets "Key=instanceids,Values=$NODE1_ID" \
  --parameters "NodeName=node-1,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP" \
  --region $REGION

# Wait, then node-2...
aws ssm send-command \
  --document-name "Wazuh-InstallIndexer-$ENV" \
  --targets "Key=instanceids,Values=$NODE2_ID" \
  --parameters "NodeName=node-2,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP" \
  --region $REGION

# Wait, then node-3...
aws ssm send-command \
  --document-name "Wazuh-InstallIndexer-$ENV" \
  --targets "Key=instanceids,Values=$NODE3_ID" \
  --parameters "NodeName=node-3,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP" \
  --region $REGION

# 4. Initialize Indexer Cluster (on node-1)
aws ssm send-command \
  --document-name "Wazuh-InitializeIndexerCluster-$ENV" \
  --targets "Key=instanceids,Values=$NODE1_ID" \
  --parameters "IndexerIP=$NODE1_IP" \
  --region $REGION

# 5. Install Manager Master (on node-1)
aws ssm send-command \
  --document-name "Wazuh-InstallManager-$ENV" \
  --targets "Key=instanceids,Values=$NODE1_ID" \
  --parameters "NodeName=node-1,NodeType=master,MasterIP=$NODE1_IP,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP,ClusterKey=$CLUSTER_KEY" \
  --region $REGION

# 6. Install Manager Worker (on node-2)
aws ssm send-command \
  --document-name "Wazuh-InstallManager-$ENV" \
  --targets "Key=instanceids,Values=$NODE2_ID" \
  --parameters "NodeName=node-2,NodeType=worker,MasterIP=$NODE1_IP,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP,ClusterKey=$CLUSTER_KEY" \
  --region $REGION

# 7. Install Dashboard (on node-3)
aws ssm send-command \
  --document-name "Wazuh-InstallDashboard-$ENV" \
  --targets "Key=instanceids,Values=$NODE3_ID" \
  --parameters "DashboardIP=$NODE3_IP,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP,WazuhAPIIP=$NODE1_IP" \
  --region $REGION
```

### Step 7: Verify Installation

```bash
# Check indexer cluster health
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=instanceids,Values=$NODE1_ID" \
  --parameters 'commands=["curl -k -u admin:admin https://localhost:9200/_cluster/health?pretty"]' \
  --region $REGION

# Check manager cluster
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=instanceids,Values=$NODE1_ID" \
  --parameters 'commands=["/var/ossec/bin/cluster_control -l"]' \
  --region $REGION

# Check dashboard via ALB
curl -sk https://YOUR-ALB-DNS-NAME.elb.amazonaws.com/app/login
```

## Access Information

### Dashboard Access

- **URL**: `https://wazuh-playground-alb-1491519345.eu-central-1.elb.amazonaws.com`
- **Default Credentials**:
  - Username: `admin`
  - Password: `admin` (CHANGE THIS!)

### API Access

- **Wazuh API**: `https://10.0.0.60:55000`
- **Indexer API**: `https://10.0.0.60:9200`

### Agent Registration

Agents should connect to the NLB:
- **NLB DNS**: `wazuh-playground-nlb-1530fc8b678ac8b3.elb.eu-central-1.amazonaws.com`
- **Registration Port**: 1514
- **Events Port**: 1515

## Troubleshooting

### Certificate Mismatch Issues

If you see SSL errors during security init, the certificates may be mismatched. Fix by:

```bash
# On each node, copy the correct node certificates
cd /etc/wazuh-indexer/certs
cp -f node-X.pem indexer.pem
cp -f node-X-key.pem indexer-key.pem
chown wazuh-indexer:wazuh-indexer indexer.pem indexer-key.pem
systemctl restart wazuh-indexer
```

### Indexer Won't Start

Check logs:
```bash
journalctl -u wazuh-indexer -n 100
```

Common issues:
- Certificate permissions (should be 400)
- Certificate ownership (should be wazuh-indexer:wazuh-indexer)
- Insufficient memory

### Dashboard Login Issues

If login doesn't work after entering credentials:
1. Ensure ALB is using HTTPS (not HTTP on port 443)
2. Verify ACM certificate is properly attached
3. Check dashboard service is running: `systemctl status wazuh-dashboard`

### SSM Command Monitoring

```bash
# List recent commands
aws ssm list-commands --region $REGION --max-results 10

# Get command output
aws ssm get-command-invocation \
  --command-id "COMMAND-ID" \
  --instance-id "INSTANCE-ID" \
  --region $REGION
```

## Security Considerations

1. **Change Default Passwords**: Immediately after installation, change:
   - Indexer admin password
   - Dashboard admin password
   - Wazuh API credentials

2. **Restrict ALB Access**: Update the ALB security group to only allow your IP ranges

3. **Enable MFA**: Configure MFA for dashboard access

4. **Network Isolation**: All Wazuh nodes are in private subnets with no public IPs

## Cost Optimization

To stop instances when not in use:
```bash
aws ec2 stop-instances \
  --instance-ids $NODE1_ID $NODE2_ID $NODE3_ID \
  --region $REGION
```

To start instances:
```bash
aws ec2 start-instances \
  --instance-ids $NODE1_ID $NODE2_ID $NODE3_ID \
  --region $REGION
```

## Clean Up

To destroy all resources:

```bash
# In reverse order
cd 03-wazuh-install && terraform destroy -var-file=terraform.tfvars
cd ../02-platform && terraform destroy -var-file=terraform.tfvars
cd ../01-infrastructure && terraform destroy -var-file=terraform.tfvars
```

## Files Structure

```
wazuh-cluster/
├── 01-infrastructure/     # VPC, subnets, security groups
├── 02-platform/           # EC2 instances, NLB, ALB
├── 03-wazuh-install/      # SSM documents for installation
│   └── ssm-documents/     # Individual SSM document YAML files
├── install-wazuh.sh       # Automated installation script
├── SSM_Documents_Installation.ps1  # Manual commands reference
└── DEPLOYMENT_GUIDE.md    # This file
```
