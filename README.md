###############################################################################
# Wazuh 3-Node Cluster - Multi-State Terraform
###############################################################################

This project is split into 3 separate Terraform states for faster applies/destroys:

```
wazuh-terraform/
├── 01-infrastructure/    # VPC, Subnets, Security Groups, Endpoints
├── 02-platform/          # EC2 instances, NLB, ALB, IAM roles
├── 03-wazuh-install/     # SSM documents, Lambda, Step Functions
└── modules/              # Shared modules (optional)
```

## Prerequisites

1. Create an S3 bucket for Terraform state:
```bash
aws s3 mb s3://your-terraform-state-bucket --region eu-central-1
```

2. Update `backend.tf` in each directory with your bucket name.

## Deployment Order

```bash
# 1. Infrastructure (VPC, Security Groups)
cd 01-infrastructure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform init
terraform apply

# 2. Platform (EC2, Load Balancers)
cd ../02-platform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars
terraform init
terraform apply

# 3. Wazuh Installation (SSM, Step Functions)
cd ../03-wazuh-install
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars (set auto_install = true)
terraform init
terraform apply
```

Destroy Order in reverse

## Install SSM (Instructions in separate file)

## Sharing State Between Layers

Each layer reads outputs from the previous layer using `terraform_remote_state`:

- `02-platform` reads VPC/subnet IDs from `01-infrastructure`
- `03-wazuh-install` reads instance IDs/IPs from `02-platform`

## Architecture

| Node | Components | Instance Type |
|------|------------|---------------|
| node-1 | Manager (Master) + Indexer | c5.large |
| node-2 | Manager (Worker) + Indexer | c5.large |
| node-3 | Indexer + Dashboard | c5.large |

## Estimated Costs (eu-central-1)

| Resource | Monthly Cost |
|----------|-------------|
| 3× c5.large | ~€200 |
| 3× 300GB gp3 | ~€75 |
| NLB + ALB | ~€50 |
| NAT Gateways (3) | ~€100 |
| **Total** | **~€425** |
