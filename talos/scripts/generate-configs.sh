#!/bin/bash
set -e

# Load configuration
if [ ! -f "config.env" ]; then
    echo "Error: config.env not found. Copy config.example.env and fill in your values."
    exit 1
fi
source config.env

echo "=== Generating Talos Configuration ==="

# Create output directory
mkdir -p _out

# Generate patch files from templates
echo "Generating patch files..."
envsubst < talos/patches/controlplane-patch.yaml.tmpl > talos/patches/controlplane-patch.yaml
envsubst < talos/patches/worker1-patch.yaml.tmpl > talos/patches/worker1-patch.yaml
envsubst < talos/patches/worker2-patch.yaml.tmpl > talos/patches/worker2-patch.yaml

# Generate Talos configs
echo "Generating Talos cluster configuration..."
talosctl gen config ${CLUSTER_NAME} https://${CP_IP}:6443 \
    --output-dir _out \
    --kubernetes-version ${KUBERNETES_VERSION} \
    --config-patch-control-plane @talos/patches/controlplane-patch.yaml \
    --config-patch-worker @talos/patches/worker1-patch.yaml

# Create worker2 config by copying and modifying worker1
echo "Creating worker2 configuration..."
cp _out/worker.yaml _out/worker2.yaml
sed -i '' "s/${WORKER1_IP}/${WORKER2_IP}/g" _out/worker2.yaml
sed -i '' "s/${WORKER1_HOSTNAME}/${WORKER2_HOSTNAME}/g" _out/worker2.yaml

echo ""
echo "=== Configuration Generated ==="
echo "Files created in _out/:"
ls -la _out/
echo ""
echo "Next step: Run ./talos/scripts/apply-configs.sh"
