#!/bin/bash
###############################################################################
# Wazuh Cluster Installation Script
# This script automates the SSM document execution for Wazuh cluster setup
#
# Usage:
#   ./install-wazuh.sh          # Auto-configure from Terraform outputs
#   ./install-wazuh.sh --manual # Use hardcoded/env values
###############################################################################

set -e

# Check if we should auto-configure from Terraform
AUTO_CONFIGURE=true
if [ "$1" = "--manual" ]; then
    AUTO_CONFIGURE=false
fi

# Function to get Terraform outputs
get_terraform_outputs() {
    local layer_dir=$1
    if [ -d "$layer_dir" ] && [ -f "$layer_dir/terraform.tfstate" ] || terraform -chdir="$layer_dir" state list &>/dev/null; then
        return 0
    fi
    return 1
}

# Auto-configure from Terraform outputs if possible
if [ "$AUTO_CONFIGURE" = true ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PLATFORM_DIR="$SCRIPT_DIR/02-platform"
    INSTALL_DIR="$SCRIPT_DIR/03-wazuh-install"

    if [ -d "$PLATFORM_DIR" ]; then
        echo "Auto-configuring from Terraform outputs..."

        # Get outputs from 02-platform
        NODE1_ID=$(terraform -chdir="$PLATFORM_DIR" output -raw node1_id 2>/dev/null || echo "")
        NODE2_ID=$(terraform -chdir="$PLATFORM_DIR" output -raw node2_id 2>/dev/null || echo "")
        NODE3_ID=$(terraform -chdir="$PLATFORM_DIR" output -raw node3_id 2>/dev/null || echo "")
        NODE1_IP=$(terraform -chdir="$PLATFORM_DIR" output -raw node1_ip 2>/dev/null || echo "")
        NODE2_IP=$(terraform -chdir="$PLATFORM_DIR" output -raw node2_ip 2>/dev/null || echo "")
        NODE3_IP=$(terraform -chdir="$PLATFORM_DIR" output -raw node3_ip 2>/dev/null || echo "")
        S3_BUCKET=$(terraform -chdir="$PLATFORM_DIR" output -raw s3_artifacts_bucket 2>/dev/null || echo "")
        ENV=$(terraform -chdir="$PLATFORM_DIR" output -raw environment 2>/dev/null || echo "playground")
        REGION=$(terraform -chdir="$PLATFORM_DIR" output -raw aws_region 2>/dev/null || echo "eu-central-1")
        DASHBOARD_URL=$(terraform -chdir="$PLATFORM_DIR" output -raw dashboard_url 2>/dev/null || echo "")
    fi

    # Get cluster key from 03-wazuh-install if available
    if [ -d "$INSTALL_DIR" ]; then
        CLUSTER_KEY=$(terraform -chdir="$INSTALL_DIR" output -raw cluster_key 2>/dev/null || echo "")
    fi
fi

# Fall back to environment variables or defaults if auto-configure failed
REGION="${REGION:-${AWS_REGION:-eu-central-1}}"
ENV="${ENV:-${WAZUH_ENV:-playground}}"

# Node IDs (from Terraform or manual input)
NODE1_ID="${NODE1_ID:-i-0f463b124fa192084}"
NODE2_ID="${NODE2_ID:-i-0eca2c12bc23b0e29}"
NODE3_ID="${NODE3_ID:-i-06a1b316bd4141864}"

# Node IPs (from Terraform or manual input)
NODE1_IP="${NODE1_IP:-10.0.0.60}"
NODE2_IP="${NODE2_IP:-10.0.1.57}"
NODE3_IP="${NODE3_IP:-10.0.2.47}"

# S3 Bucket for certificates
S3_BUCKET="${S3_BUCKET:-wazuh-playground-artifacts-01e51fce}"

# Dashboard URL
DASHBOARD_URL="${DASHBOARD_URL:-https://playground.oktopay-dev.eu}"

# Cluster key (generate or use existing)
CLUSTER_KEY="${CLUSTER_KEY:-$(openssl rand -hex 16)}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to wait for SSM command to complete
wait_for_command() {
    local command_id=$1
    local instance_id=$2
    local description=$3
    local timeout=${4:-600}  # Default 10 minutes
    local elapsed=0
    local interval=10

    log_info "Waiting for: $description (Command: $command_id)"

    while [ $elapsed -lt $timeout ]; do
        status=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --region "$REGION" \
            --query "Status" \
            --output text 2>/dev/null || echo "Pending")

        case $status in
            "Success")
                log_success "$description completed successfully"
                return 0
                ;;
            "Failed"|"Cancelled"|"TimedOut")
                log_error "$description failed with status: $status"
                # Show error output
                aws ssm get-command-invocation \
                    --command-id "$command_id" \
                    --instance-id "$instance_id" \
                    --region "$REGION" \
                    --query "StandardErrorContent" \
                    --output text 2>/dev/null || true
                return 1
                ;;
            "InProgress"|"Pending")
                echo -n "."
                sleep $interval
                elapsed=$((elapsed + interval))
                ;;
            *)
                echo -n "."
                sleep $interval
                elapsed=$((elapsed + interval))
                ;;
        esac
    done

    log_error "$description timed out after ${timeout}s"
    return 1
}

# Function to run SSM command and wait
run_ssm_command() {
    local doc_name=$1
    local target_instances=$2
    local parameters=$3
    local description=$4
    local timeout=${5:-600}

    log_info "Running: $description"
    log_info "Document: $doc_name"
    log_info "Targets: $target_instances"

    # Run SSM command
    command_id=$(aws ssm send-command \
        --document-name "$doc_name" \
        --targets "Key=instanceids,Values=$target_instances" \
        --parameters "$parameters" \
        --region "$REGION" \
        --timeout-seconds $timeout \
        --query "Command.CommandId" \
        --output text)

    if [ -z "$command_id" ]; then
        log_error "Failed to start SSM command"
        return 1
    fi

    log_info "Command ID: $command_id"

    # Wait for command on each instance
    IFS=',' read -ra instances <<< "$target_instances"
    for instance in "${instances[@]}"; do
        if ! wait_for_command "$command_id" "$instance" "$description on $instance" "$timeout"; then
            return 1
        fi
    done

    return 0
}

# Function to check if instances are running and SSM is ready
check_instances() {
    log_info "Checking instance status..."

    for node_id in $NODE1_ID $NODE2_ID $NODE3_ID; do
        state=$(aws ec2 describe-instances \
            --instance-ids "$node_id" \
            --region "$REGION" \
            --query "Reservations[0].Instances[0].State.Name" \
            --output text)

        if [ "$state" != "running" ]; then
            log_warning "Instance $node_id is $state, starting..."
            aws ec2 start-instances --instance-ids "$node_id" --region "$REGION" > /dev/null
        fi
    done

    log_info "Waiting for instances to be running..."
    aws ec2 wait instance-running \
        --instance-ids $NODE1_ID $NODE2_ID $NODE3_ID \
        --region "$REGION"

    log_success "All instances are running"

    log_info "Waiting for SSM agent to be ready..."
    sleep 30  # Give SSM agent time to connect

    # Verify SSM connectivity
    for node_id in $NODE1_ID $NODE2_ID $NODE3_ID; do
        for i in {1..12}; do
            status=$(aws ssm describe-instance-information \
                --filters "Key=InstanceIds,Values=$node_id" \
                --region "$REGION" \
                --query "InstanceInformationList[0].PingStatus" \
                --output text 2>/dev/null || echo "Offline")

            if [ "$status" = "Online" ]; then
                log_success "SSM agent online for $node_id"
                break
            fi

            if [ $i -eq 12 ]; then
                log_error "SSM agent not responding for $node_id after 2 minutes"
                return 1
            fi

            echo -n "."
            sleep 10
        done
    done

    return 0
}

# Print configuration
print_config() {
    echo ""
    echo "=============================================="
    echo "       Wazuh Cluster Installation"
    echo "=============================================="
    echo ""
    echo "Configuration:"
    echo "  Region:     $REGION"
    echo "  Environment: $ENV"
    echo "  S3 Bucket:  $S3_BUCKET"
    echo ""
    echo "Nodes:"
    echo "  Node 1: $NODE1_ID ($NODE1_IP) - Manager Master + Indexer"
    echo "  Node 2: $NODE2_ID ($NODE2_IP) - Manager Worker + Indexer"
    echo "  Node 3: $NODE3_ID ($NODE3_IP) - Indexer + Dashboard"
    echo ""
    echo "=============================================="
    echo ""
}

# Main installation flow
main() {
    print_config

    # Step 0: Check instances
    log_info "Step 0: Checking instances..."
    if ! check_instances; then
        log_error "Instance check failed"
        exit 1
    fi

    # Step 1: Generate Certificates (on node-1)
    log_info "Step 1: Generating certificates on node-1..."
    if ! run_ssm_command \
        "Wazuh-GenerateCertificates-$ENV" \
        "$NODE1_ID" \
        "Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP,S3Bucket=$S3_BUCKET" \
        "Generate certificates" \
        300; then
        log_error "Certificate generation failed"
        exit 1
    fi

    # Step 2: Distribute Certificates (on all nodes)
    log_info "Step 2: Distributing certificates to all nodes..."

    # Node 1
    if ! run_ssm_command \
        "Wazuh-DistributeCertificates-$ENV" \
        "$NODE1_ID" \
        "S3Bucket=$S3_BUCKET,NodeName=node-1" \
        "Distribute certificates to node-1" \
        300; then
        log_error "Certificate distribution to node-1 failed"
        exit 1
    fi

    # Node 2
    if ! run_ssm_command \
        "Wazuh-DistributeCertificates-$ENV" \
        "$NODE2_ID" \
        "S3Bucket=$S3_BUCKET,NodeName=node-2" \
        "Distribute certificates to node-2" \
        300; then
        log_error "Certificate distribution to node-2 failed"
        exit 1
    fi

    # Node 3
    if ! run_ssm_command \
        "Wazuh-DistributeCertificates-$ENV" \
        "$NODE3_ID" \
        "S3Bucket=$S3_BUCKET,NodeName=node-3" \
        "Distribute certificates to node-3" \
        300; then
        log_error "Certificate distribution to node-3 failed"
        exit 1
    fi

    # Step 3: Install Indexer (on all nodes, sequentially for cluster formation)
    log_info "Step 3: Installing Wazuh Indexer on all nodes..."

    # Node 1 first (will be initial master)
    if ! run_ssm_command \
        "Wazuh-InstallIndexer-$ENV" \
        "$NODE1_ID" \
        "NodeName=node-1,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP" \
        "Install Indexer on node-1" \
        900; then
        log_error "Indexer installation on node-1 failed"
        exit 1
    fi

    # Node 2
    if ! run_ssm_command \
        "Wazuh-InstallIndexer-$ENV" \
        "$NODE2_ID" \
        "NodeName=node-2,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP" \
        "Install Indexer on node-2" \
        900; then
        log_error "Indexer installation on node-2 failed"
        exit 1
    fi

    # Node 3
    if ! run_ssm_command \
        "Wazuh-InstallIndexer-$ENV" \
        "$NODE3_ID" \
        "NodeName=node-3,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP" \
        "Install Indexer on node-3" \
        900; then
        log_error "Indexer installation on node-3 failed"
        exit 1
    fi

    # Wait for cluster to form
    log_info "Waiting for indexer cluster to stabilize..."
    sleep 30

    # Step 4: Initialize Indexer Cluster (on node-1)
    log_info "Step 4: Initializing indexer cluster..."
    if ! run_ssm_command \
        "Wazuh-InitializeIndexerCluster-$ENV" \
        "$NODE1_ID" \
        "IndexerIP=$NODE1_IP" \
        "Initialize indexer cluster" \
        300; then
        log_error "Indexer cluster initialization failed"
        exit 1
    fi

    # Step 5: Install Manager Master (on node-1)
    log_info "Step 5: Installing Wazuh Manager (master) on node-1..."
    if ! run_ssm_command \
        "Wazuh-InstallManager-$ENV" \
        "$NODE1_ID" \
        "NodeName=node-1,NodeType=master,MasterIP=$NODE1_IP,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP,ClusterKey=$CLUSTER_KEY" \
        "Install Manager master" \
        900; then
        log_error "Manager master installation failed"
        exit 1
    fi

    # Step 6: Install Manager Worker (on node-2)
    log_info "Step 6: Installing Wazuh Manager (worker) on node-2..."
    if ! run_ssm_command \
        "Wazuh-InstallManager-$ENV" \
        "$NODE2_ID" \
        "NodeName=node-2,NodeType=worker,MasterIP=$NODE1_IP,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP,ClusterKey=$CLUSTER_KEY" \
        "Install Manager worker" \
        900; then
        log_error "Manager worker installation failed"
        exit 1
    fi

    # Step 7: Install Dashboard (on node-3)
    log_info "Step 7: Installing Wazuh Dashboard on node-3..."
    if ! run_ssm_command \
        "Wazuh-InstallDashboard-$ENV" \
        "$NODE3_ID" \
        "DashboardIP=$NODE3_IP,Node1IP=$NODE1_IP,Node2IP=$NODE2_IP,Node3IP=$NODE3_IP,WazuhAPIIP=$NODE1_IP" \
        "Install Dashboard" \
        900; then
        log_error "Dashboard installation failed"
        exit 1
    fi

    # Final summary
    echo ""
    echo "=============================================="
    echo "       Installation Complete!"
    echo "=============================================="
    echo ""
    log_success "Wazuh cluster installation completed successfully!"
    echo ""

    # Get dashboard URL from terraform or use custom domain if set
    DASHBOARD_URL="${DASHBOARD_URL:-https://playground.oktopay-dev.eu}"
    echo "Dashboard URL: $DASHBOARD_URL"
    echo ""
    echo "Default Credentials:"
    echo "  Username: admin"
    echo "  Password: admin (CHANGE THIS!)"
    echo ""
    echo "Cluster Key: $CLUSTER_KEY"
    echo "(Save this key for adding worker nodes)"
    echo ""
    echo "Verify cluster health with:"
    echo "  curl -k -u admin:admin https://$NODE1_IP:9200/_cluster/health?pretty"
    echo "  curl -k -u admin:admin https://$NODE1_IP:9200/_cat/nodes?v"
    echo ""
    echo "Verify dashboard with:"
    echo "  curl -sk $DASHBOARD_URL/api/status | grep -o '\"state\":\"[^\"]*\"'"
    echo ""
}

# Run main
main "$@"
