#!/bin/bash
set -e

###############################################################################
# Wazuh Node - Minimal Bootstrap (Disk & System Tuning Only)
# Node: ${node_name}
# Role: ${node_role}
###############################################################################

exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=== Bootstrap starting for ${node_name} at $(date) ==="

###############################################################################
# 1. Install AWS CLI (not included by default on AL2023)
###############################################################################

echo "[1/5] Installing AWS CLI..."
dnf install -y awscli-2

###############################################################################
# 2. Format and Mount Data Volume
###############################################################################

echo "[2/5] Setting up data volume..."

sleep 10

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

if ! blkid "$DATA_DEVICE" | grep -q ext4; then
    echo "Formatting $DATA_DEVICE with ext4..."
    mkfs.ext4 -L wazuh-data "$DATA_DEVICE"
fi

mkdir -p /var/ossec
mkdir -p /var/lib/wazuh-indexer

if ! grep -q "wazuh-data" /etc/fstab; then
    echo "LABEL=wazuh-data /var/ossec ext4 defaults,nofail 0 2" >> /etc/fstab
fi

mount -a || mount "$DATA_DEVICE" /var/ossec
echo "Data volume mounted: $(df -h /var/ossec | tail -1)"

###############################################################################
# 3. System Tuning
###############################################################################

echo "[3/5] Applying system tuning..."

cat >> /etc/security/limits.conf << 'EOF'
* soft nofile 65536
* hard nofile 65536
wazuh soft nofile 65536
wazuh hard nofile 65536
wazuh-indexer soft nofile 65536
wazuh-indexer hard nofile 65536
EOF

cat >> /etc/sysctl.conf << 'EOF'
vm.max_map_count=262144
vm.swappiness=1
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
EOF
sysctl -p

swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

###############################################################################
# 4. Set Hostname
###############################################################################

echo "[4/5] Setting hostname..."
hostnamectl set-hostname "wazuh-${node_name}"
echo "127.0.0.1 wazuh-${node_name}" >> /etc/hosts

###############################################################################
# 5. Node Metadata
###############################################################################

echo "[5/5] Writing node metadata..."
cat > /etc/wazuh-node-info << EOF
NODE_NAME=${node_name}
NODE_ROLE=${node_role}
MANAGER_TYPE=${manager_type}
ENVIRONMENT=${environment}
BOOTSTRAP_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

echo "=== Bootstrap complete at $(date) ==="
