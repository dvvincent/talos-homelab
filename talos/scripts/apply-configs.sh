#!/bin/bash
set -e

# Load configuration
source config.env

export TALOSCONFIG="_out/talosconfig"

echo "=== Applying Talos Configurations ==="
echo ""
echo "This script expects the VMs to be booted from the Talos ISO."
echo "Nodes should have temporary DHCP addresses."
echo ""

# Function to apply config
apply_config() {
    local node_name=$1
    local target_ip=$2
    local config_file=$3
    
    echo "Applying config to ${node_name}..."
    read -p "Enter current DHCP IP for ${node_name} (target: ${target_ip}): " current_ip
    
    if [ -z "$current_ip" ]; then
        echo "Skipping ${node_name}"
        return
    fi
    
    talosctl apply-config --insecure --nodes ${current_ip} --file ${config_file}
    echo "${node_name} configured. It will reboot and come up on ${target_ip}"
    echo ""
}

# Apply control plane config
apply_config "Control Plane (${CP_HOSTNAME})" "${CP_IP}" "_out/controlplane.yaml"

# Apply worker 1 config
apply_config "Worker 1 (${WORKER1_HOSTNAME})" "${WORKER1_IP}" "_out/worker.yaml"

# Apply worker 2 config
apply_config "Worker 2 (${WORKER2_HOSTNAME})" "${WORKER2_IP}" "_out/worker2.yaml"

echo ""
echo "=== Configurations Applied ==="
echo ""
echo "Wait 2-3 minutes for nodes to install and reboot."
echo "Then run: ./talos/scripts/bootstrap.sh"
