# Wazuh Cluster Ansible Deployment

Ansible playbooks for deploying a production Wazuh cluster on AWS.

## Architecture

- 2x Wazuh Indexers (OpenSearch cluster)
- 1x Wazuh Manager Master
- 2x Wazuh Manager Workers
- 1x Wazuh Dashboard (on master node)

## Prerequisites

1. **Terraform infrastructure deployed** - EC2 instances running
2. **Ansible installed** on your local machine:
   ```bash
   pip install ansible
   ```
3. **SSH key** at `~/.ssh/wazuh-cluster-key`
4. **Bastion host** public IP from Terraform output

## Quick Start

### 1. Update Inventory

Edit `inventory/hosts.ini` and replace `BASTION_PUBLIC_IP_HERE` with your actual bastion IP:

```bash
# Get bastion IP from Terraform
cd ../wazuh-terraform
terraform output bastion_public_ip

# Update inventory (replace X.X.X.X with actual IP)
sed -i 's/BASTION_PUBLIC_IP_HERE/X.X.X.X/g' inventory/hosts.ini
```

### 2. Test Connectivity

```bash
# Test bastion connection
ansible bastion -m ping

# Test all nodes through bastion
ansible wazuh -m ping
```

### 3. Deploy Cluster

```bash
# Full deployment
ansible-playbook site.yml

# Or run specific stages:
ansible-playbook site.yml --tags certs        # Generate certificates only
ansible-playbook site.yml --tags indexer      # Deploy indexers only
ansible-playbook site.yml --tags manager      # Deploy managers only
ansible-playbook site.yml --tags dashboard    # Deploy dashboard only
```

### 4. Access Dashboard

```bash
# Create SSH tunnel
ssh -L 8443:10.172.11.9:443 -i ~/.ssh/wazuh-cluster-key ec2-user@<BASTION_IP>

# Open browser
open https://localhost:8443

# Login: admin / admin (CHANGE THIS!)
```

## Directory Structure

```
wazuh-ansible/
├── ansible.cfg              # Ansible configuration
├── site.yml                 # Main playbook
├── cluster-key.txt          # Generated cluster key (gitignore this!)
├── certs/                   # Generated certificates (gitignore this!)
├── inventory/
│   ├── hosts.ini            # Inventory file
│   └── group_vars/
│       └── all.yml          # Common variables
└── roles/
    ├── certificates/        # Certificate generation
    ├── common/              # Common system configuration
    ├── indexer/             # Wazuh Indexer setup
    ├── manager/             # Wazuh Manager setup
    └── dashboard/           # Wazuh Dashboard setup
```

## Useful Commands

```bash
# Check cluster status
ansible master -m command -a "/var/ossec/bin/cluster_control -l" --become

# Check indexer health
ansible indexers[0] -m uri -a "url=https://localhost:9200/_cluster/health user=admin password=admin validate_certs=no" --become

# Restart a service
ansible indexers -m systemd -a "name=wazuh-indexer state=restarted" --become
ansible managers -m systemd -a "name=wazuh-manager state=restarted" --become

# View logs
ansible master -m command -a "tail -50 /var/ossec/logs/cluster.log" --become
```

## Customization

### Change Node IPs

Edit `inventory/group_vars/all.yml`:

```yaml
indexer_1_ip: "10.172.11.7"
indexer_2_ip: "10.172.11.8"
# ... etc
```

### Change JVM Heap Size

Edit `inventory/group_vars/all.yml`:

```yaml
indexer_jvm_heap: "4g"  # For t3.large with 8GB RAM
```

### Add More Workers

1. Add to `inventory/hosts.ini`:
   ```ini
   [workers]
   worker-3 ansible_host=10.172.11.12 node_name=worker-3 node_type=worker
   ```

2. Add to `inventory/group_vars/all.yml`:
   ```yaml
   worker_3_ip: "10.172.11.12"
   ```

3. Update certificate config in `roles/certificates/templates/config.yml.j2`

4. Re-run deployment:
   ```bash
   ansible-playbook site.yml --tags certs,manager
   ```

## Troubleshooting

### SSH Connection Issues

```bash
# Test direct connection to bastion
ssh -i ~/.ssh/wazuh-cluster-key ec2-user@<BASTION_IP>

# Test jump through bastion
ssh -i ~/.ssh/wazuh-cluster-key -J ec2-user@<BASTION_IP> ec2-user@10.172.11.9
```

### Certificate Issues

```bash
# Regenerate certificates
rm -rf certs/ cluster-key.txt
ansible-playbook site.yml --tags certs
```

### Service Won't Start

```bash
# Check logs
ansible <host> -m command -a "journalctl -u wazuh-indexer -n 100" --become
ansible <host> -m command -a "journalctl -u wazuh-manager -n 100" --become

# Check config syntax
ansible master -m command -a "/var/ossec/bin/wazuh-analysisd -t" --become
```

## Security Notes

1. **Change default passwords** immediately after deployment
2. **Secure the cluster-key.txt** - don't commit to git
3. **Rotate certificates** periodically
4. **Restrict bastion access** to known IPs only

## Files to Gitignore

Add to `.gitignore`:
```
certs/
cluster-key.txt
*.retry
```
