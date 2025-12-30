# Wazuh Cluster - GitHub Actions CI/CD

Terraform CI/CD pipeline with GitHub Actions using OIDC authentication (no static AWS credentials).

## Features

- **OIDC Authentication** - No long-lived AWS credentials stored in GitHub
- **Lint & Validate** - terraform fmt, validate, and TFLint checks
- **Security Scanning** - Trivy scans for HIGH/CRITICAL issues (blocks on CRITICAL)
- **Plan Artifacts** - Plan JSON, human-readable output, and resource graph saved for 90 days
- **PR Comments** - Automatic plan output posted to pull requests
- **Manual Approval** - Apply requires approval via GitHub Environments
- **Destroy Protection** - Separate environment with additional approval for destroy

## Setup Instructions

### 1. Deploy IAM Resources (One-time)

First, deploy the OIDC provider and IAM role. Run this locally with admin credentials:

```bash
cd iam-github-oidc

terraform init
terraform apply \
  -var="github_org=YOUR_GITHUB_ORG" \
  -var="github_repo=YOUR_REPO_NAME" \
  -var="aws_region=eu-west-1"
```

This creates:
- GitHub OIDC Provider (account-wide)
- IAM Role for GitHub Actions
- IAM Policy with scoped Terraform permissions
- S3 bucket for Terraform state
- DynamoDB table for state locking

### 2. Configure GitHub Secrets

Go to your repository: **Settings → Secrets and variables → Actions**

Add these secrets:

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `AWS_ROLE_ARN` | `arn:aws:iam::ACCOUNT:role/oktopay-pci-github-actions-terraform` | Output from step 1 |
| `TRUSTED_SSH_CIDR` | `1.2.3.4/32` | Your office/home IP for bastion SSH access |

### 3. Configure GitHub Environments

Go to: **Settings → Environments**

#### Create `production` environment:
1. Click "New environment" → Name: `production`
2. Add **Required reviewers** (yourself or team members)
3. Optionally set **Deployment branches** to `main` only

#### Create `production-destroy` environment:
1. Click "New environment" → Name: `production-destroy`
2. Add **Required reviewers** (recommend 2+ people)
3. This adds extra protection against accidental destroys

### 4. Update Terraform Backend

Update your `terraform/providers.tf` to use the S3 backend:

```hcl
terraform {
  backend "s3" {
    bucket         = "oktopay-pci-terraform-state"
    key            = "wazuh-cluster/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "oktopay-pci-terraform-locks"
  }
}
```

### 5. Push and Test

```bash
git add .
git commit -m "Add Terraform CI/CD"
git push origin main
```

## Workflow Triggers

| Trigger | Behavior |
|---------|----------|
| Push to `main` | Lint → Security → Plan → Apply (with approval) |
| Pull Request | Lint → Security → Plan (comment on PR) |
| Manual (`workflow_dispatch`) | Choose: plan, apply, or destroy |

## Artifacts

Each run saves the following artifacts (90 day retention):

| Artifact | Contents |
|----------|----------|
| `terraform-plan-{run}-{sha}` | `tfplan`, `tfplan.json`, `tfplan.txt`, `plan_summary.md`, `graph.dot`, `graph.png`, `graph.svg` |
| `terraform-outputs-{run}-{sha}` | `outputs.json`, `outputs.txt` |
| `trivy-security-report` | Security scan results |

## Directory Structure

```
.
├── .github/
│   └── workflows/
│       └── terraform.yml      # CI/CD workflow
├── iam-github-oidc/
│   └── main.tf                # IAM resources (deploy once)
└── terraform/
    ├── .tflint.hcl            # TFLint configuration
    ├── providers.tf
    ├── variables.tf
    └── ... (your Terraform files)
```

## Security Notes

1. **OIDC vs Static Credentials**: OIDC provides short-lived credentials scoped to specific repos/branches
2. **IAM Permissions**: The policy is scoped to resources prefixed with `oktopay-pci-`
3. **Trivy Scanning**: Blocks pipeline on CRITICAL findings, reports HIGH findings
4. **Environment Protection**: Requires manual approval before apply/destroy
5. **State Encryption**: S3 bucket uses KMS encryption, versioning enabled

## Troubleshooting

### "Not authorized to perform sts:AssumeRoleWithWebIdentity"
- Check that `AWS_ROLE_ARN` secret matches the role ARN
- Verify the OIDC provider thumbprint is correct
- Ensure repo name in IAM policy matches exactly

### "No changes" but infrastructure differs
- Someone may have made manual changes
- Run `terraform refresh` locally to sync state

### TFLint failures
- Run `terraform fmt -recursive` locally before pushing
- Check `.tflint.hcl` for rule configurations

## Manual Operations

For emergency or debugging, you can still run Terraform locally:

```bash
# Configure AWS credentials locally
aws sso login --profile your-profile

# Or assume the GitHub Actions role
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT:role/oktopay-pci-github-actions-terraform \
  --role-session-name local-debug

cd terraform
terraform init
terraform plan
```
