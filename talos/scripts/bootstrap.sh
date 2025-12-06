#!/bin/bash
set -e

# Load configuration
source config.env

export TALOSCONFIG="_out/talosconfig"

echo "=== Bootstrapping Talos Cluster ==="
echo ""

# Check if control plane is reachable
echo "Checking if control plane (${CP_IP}) is reachable..."
if ! ping -c 1 -W 3 ${CP_IP} > /dev/null 2>&1; then
    echo "Error: Control plane at ${CP_IP} is not reachable."
    echo "Wait for the node to boot and try again."
    exit 1
fi

echo "Control plane is reachable. Bootstrapping etcd..."
talosctl bootstrap --nodes ${CP_IP}

echo ""
echo "Waiting for Kubernetes API to be ready..."
sleep 30

echo "Generating kubeconfig..."
talosctl kubeconfig --nodes ${CP_IP} ./kubeconfig

export KUBECONFIG=$(pwd)/kubeconfig

echo ""
echo "Waiting for nodes to become ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

echo ""
echo "=== Cluster Bootstrapped ==="
echo ""
kubectl get nodes -o wide

echo ""
echo "Kubeconfig saved to: ./kubeconfig"
echo "Export it with: export KUBECONFIG=$(pwd)/kubeconfig"
echo ""
echo "Next step: Run ./deploy.sh to install core components"
