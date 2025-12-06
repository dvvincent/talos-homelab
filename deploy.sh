#!/bin/bash
set -e

# Load configuration
source config.env

export KUBECONFIG=$(pwd)/kubeconfig

echo "=== Deploying Core Components ==="
echo ""

# =====================
# MetalLB
# =====================
echo "Installing MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

echo "Waiting for MetalLB pods..."
kubectl wait --namespace metallb-system \
    --for=condition=ready pod \
    --selector=app=metallb \
    --timeout=90s

echo "Configuring MetalLB IP pool..."
kubectl apply -f manifests/core/metallb-config.yaml

echo "✓ MetalLB installed"
echo ""

# =====================
# Traefik
# =====================
echo "Installing Traefik..."
helm repo add traefik https://traefik.github.io/charts 2>/dev/null || true
helm repo update

kubectl create namespace traefik --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install traefik traefik/traefik \
    --namespace traefik \
    --set ports.web.exposedPort=80 \
    --set ports.websecure.exposedPort=443 \
    --set service.type=LoadBalancer \
    --wait

echo "✓ Traefik installed"
echo ""

# =====================
# Longhorn
# =====================
echo "Installing Longhorn..."
kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace longhorn-system \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/warn=privileged \
    --overwrite

helm repo add longhorn https://charts.longhorn.io 2>/dev/null || true
helm repo update

helm upgrade --install longhorn longhorn/longhorn \
    --namespace longhorn-system \
    --set defaultSettings.defaultDataPath="/var/lib/longhorn" \
    --set persistence.defaultClass=true \
    --set persistence.defaultClassReplicaCount=2 \
    --wait --timeout 10m

echo "✓ Longhorn installed"
echo ""

# =====================
# cert-manager
# =====================
echo "Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.1/cert-manager.yaml

echo "Waiting for cert-manager pods..."
kubectl wait --namespace cert-manager \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/instance=cert-manager \
    --timeout=120s

echo "✓ cert-manager installed"
echo ""

# =====================
# cloudflare-operator
# =====================
echo "Installing cloudflare-operator..."
kubectl apply -k 'https://github.com/adyanth/cloudflare-operator.git/config/default?ref=v0.13.1'

echo "Waiting for cloudflare-operator..."
kubectl wait --namespace cloudflare-operator-system \
    --for=condition=ready pod \
    --selector=control-plane=controller-manager \
    --timeout=120s

echo "✓ cloudflare-operator installed"
echo ""

# =====================
# Summary
# =====================
echo "=== Core Components Deployed ==="
echo ""
echo "Installed:"
echo "  ✓ MetalLB (IP pool: ${METALLB_IP_RANGE})"
echo "  ✓ Traefik (LoadBalancer)"
echo "  ✓ Longhorn (Distributed storage)"
echo "  ✓ cert-manager (SSL certificates)"
echo "  ✓ cloudflare-operator (Tunnel management)"
echo ""
echo "Next steps:"
echo "  1. Create Cloudflare secret: ./talos/scripts/create-cloudflare-secret.sh"
echo "  2. Apply cert-manager issuer: kubectl apply -f manifests/core/cert-manager-issuer.yaml"
echo "  3. Deploy Cloudflare tunnel: kubectl apply -f manifests/cloudflare/"
echo "  4. Deploy apps: kubectl apply -f manifests/apps/ghost/"
