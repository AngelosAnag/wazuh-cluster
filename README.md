# Wazuh 3-Node Cluster - Terraform

This Terraform configuration deploys a **fully automated**, production-ready 3-node Wazuh cluster on AWS.

## Architecture

| Node | Components | AZ |
|------|------------|-----|
| node-1 | Wazuh Manager (Master) + Indexer | eu-central-1a |
| node-2 | Wazuh Manager (Worker) + Indexer | eu-central-1b |
| node-3 | Wazuh Indexer + Dashboard | eu-central-1c |

## Features

- **Fully automated** - Step Functions orchestrates entire Wazuh installation
- **No SSH keys required** - All access via SSM Session Manager
- **Lambda + Step Functions** for reliable, observable installation
- **Parallel execution** - Indexer installs run simultaneously on all 3 nodes
- **S3 bucket** for secure certificate distribution
- **CloudWatch Logs** for installation monitoring
- **PCI-ready** - VPC Flow Logs, encrypted EBS, IMDSv2

## Prerequisites

1. AWS CLI configured with appropriate credentials
2. Terraform >= 1.5.0
3. (Optional) ACM certificate for HTTPS on the dashboard

## Directory Structure

```
.
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example
│
├── infrastructure/            # VPC, Subnets, Security Groups
│
└── platform/
    ├── main.tf               # EC2, NLB, ALB
    ├── ssm.tf                # SSM Documents
    ├── automation.tf         # Lambda + Step Functions
    ├── templates/
    │   └── user_data.sh      # Minimal bootstrap
    ├── lambda/
    │   ├── ssm_orchestrator.py
    │   └── state_machine.json.tpl
    └── ssm-documents/
        ├── 01-generate-certificates.yaml
        ├── 02-distribute-certificates.yaml
        ├── 03-install-indexer.yaml
        ├── 04-initialize-indexer-cluster.yaml
        ├── 05-install-manager.yaml
        └── 06-install-dashboard.yaml
```

## Quick Start

### 1. Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
aws_region          = "eu-central-1"
environment         = "prod"
allowed_cidr_blocks = ["YOUR_OFFICE_IP/32"]
auto_install        = true  # Set to false for manual trigger
```

### 2. Deploy Everything

```bash
terraform init
terraform plan
terraform apply
```

That's it! The installation runs automatically:

1. Infrastructure deploys (~5 min)
2. Step Functions triggers automatically
3. Installation completes (~15-20 min)

### 3. Monitor Progress

```bash
# Get the console URL
terraform output step_function_console_url

# Or via CLI
terraform output step_function_arn
aws stepfunctions describe-execution --execution-arn <arn>
```

### 4. Access Dashboard

```bash
terraform output dashboard_url
```

Default credentials: `admin` / `admin` (change immediately!)

## Installation Flow

```
terraform apply
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│                   Step Functions                         │
├─────────────────────────────────────────────────────────┤
│  1. Wait for SSM Agents (all nodes)                     │
│  2. Generate Certificates (node-1)                      │
│  3. Distribute Certificates (all nodes)                 │
│  4. Install Indexer (parallel on all 3 nodes)           │
│  5. Initialize Indexer Cluster (node-1)                 │
│  6. Install Manager Master (node-1)                     │
│  7. Install Manager Worker (node-2)                     │
│  8. Install Dashboard (node-3)                          │
└─────────────────────────────────────────────────────────┘
      │
      ▼
   Complete!
```

## Manual Trigger (if auto_install = false)

```bash
aws stepfunctions start-execution \
  --state-machine-arn $(terraform output -raw step_function_arn) \
  --name "install-$(date +%Y%m%d-%H%M%S)"
```

## Connecting to Nodes

Use SSM Session Manager:

```bash
terraform output ssh_connection_commands
aws ssm start-session --target <instance-id> --region eu-central-1
```

## Security Groups

| Port | Purpose | Source |
|------|---------|--------|
| 1514 | Agent registration | VPC CIDR |
| 1515 | Agent events | VPC CIDR |
| 1516 | Manager cluster | Self (nodes) |
| 9200 | Indexer API | Self (nodes) |
| 9300 | Indexer cluster | Self (nodes) |
| 55000 | Wazuh API | Self (nodes) |
| 443 | Dashboard | ALB |

## Estimated Costs (eu-central-1)

| Resource | Monthly Cost |
|----------|-------------|
| 3× m5.xlarge | ~€420 |
| 3× 300GB gp3 | ~€75 |
| NLB + ALB | ~€50 |
| NAT Gateways (3) | ~€100 |
| Lambda + Step Functions | ~€1 |
| **Total** | **~€646** |

## Troubleshooting

### Check Step Functions Execution

```bash
# List recent executions
aws stepfunctions list-executions \
  --state-machine-arn $(terraform output -raw step_function_arn) \
  --max-results 5

# Get execution details
aws stepfunctions describe-execution --execution-arn <execution-arn>

# Get execution history (shows which step failed)
aws stepfunctions get-execution-history --execution-arn <execution-arn>
```

### Check Lambda Logs

```bash
aws logs tail /aws/lambda/wazuh-prod-ssm-orchestrator --follow
```

### Check SSM Command Output

```bash
aws ssm list-commands --max-results 10
aws ssm get-command-invocation --command-id <id> --instance-id <id>
```

### Connect to Instance for Debugging

```bash
aws ssm start-session --target <instance-id>

# Check indexer logs
journalctl -u wazuh-indexer -f

# Check manager logs  
journalctl -u wazuh-manager -f

# Check dashboard logs
journalctl -u wazuh-dashboard -f
```

### Re-run Installation

If installation fails, you can re-trigger:

```bash
aws stepfunctions start-execution \
  --state-machine-arn $(terraform output -raw step_function_arn) \
  --name "retry-$(date +%Y%m%d-%H%M%S)"
```

## Cleanup

```bash
terraform destroy
```

**Note:** EBS data volumes have `delete_on_termination = false` - manually delete if needed.
