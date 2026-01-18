#!/bin/bash
set -e

###############################################################################
# Wazuh Node - Minimal Bootstrap (Disk & System Tuning Only)
# Node: ${node_name}
# Role: ${node_role}
#
# This script ONLY handles:
#   1. EBS volume formatting and mounting
#   2. Kernel/system tuning for Wazuh Indexer
#   3. Node metadata
#
# All Wazuh installation is done via SSM Documents.
###############################################################################

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=== Bootstrap starting for ${node_name} at $(date) ==="

###############################################################################
# 1. Format and Mount Data Volume
###############################################################################

echo "[1/4] Setting up data volume..."

# Wait for EBS volume to be attached
sleep 20

# Find the data volume (NVMe device on Nitro instances)
DATA_DEVICE=""
for device in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
    if [ -b "$device" ]; then
        DATA_DEVICE="$device"
        break
    fi
done

if [ -z "$DATA_DEVICE" ]; then
    echo "ERROR: Data volume not found!"
    exit 1
fi

echo "Found data device: $DATA_DEVICE"

# Format if not already formatted
if ! blkid "$DATA_DEVICE" | grep -q ext4; then
    echo "Formatting $DATA_DEVICE with ext4..."
    mkfs.ext4 -L wazuh-data "$DATA_DEVICE"
fi

# Create mount points
mkdir -p /var/ossec
mkdir -p /var/lib/wazuh-indexer

# Add to fstab if not already present
if ! grep -q "wazuh-data" /etc/fstab; then
    echo "LABEL=wazuh-data /var/ossec ext4 defaults,nofail 0 2" >> /etc/fstab
fi

# Mount
mount -a || mount "$DATA_DEVICE" /var/ossec
echo "Data volume mounted: $(df -h /var/ossec | tail -1)"

###############################################################################
# 2. System Tuning (required before Wazuh Indexer install)
###############################################################################

echo "[2/4] Applying system tuning..."

# File descriptors
cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 65536
* hard nofile 65536
wazuh soft nofile 65536
wazuh hard nofile 65536
wazuh-indexer soft nofile 65536
wazuh-indexer hard nofile 65536
EOF

# Kernel parameters for OpenSearch
cat >> /etc/sysctl.conf << 'EOF'
vm.max_map_count=262144
vm.swappiness=1
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
EOF
sysctl -p

# Disable swap (OpenSearch requirement)
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

###############################################################################
# 3. Set Hostname
###############################################################################

echo "[3/4] Setting hostname..."
hostnamectl set-hostname "wazuh-${node_name}"
echo "127.0.0.1 wazuh-${node_name}" >> /etc/hosts

###############################################################################
# 4. Node Metadata (for SSM documents to read)
###############################################################################

echo "[4/4] Writing node metadata..."
cat > /etc/wazuh-node-info << EOF
NODE_NAME=${node_name}
NODE_ROLE=${node_role}
MANAGER_TYPE=${manager_type}
ENVIRONMENT=${environment}
BOOTSTRAP_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

###############################################################################
# Done
###############################################################################

echo "=== Bootstrap complete at $(date) ==="
echo "Node ${node_name} ready for Wazuh installation via SSM"
