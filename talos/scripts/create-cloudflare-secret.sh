#!/bin/bash
set -e

# Load configuration
source config.env

export KUBECONFIG=$(pwd)/kubeconfig

echo "=== Creating Cloudflare Secret ==="
echo ""

# Check required variables
if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ "$CLOUDFLARE_API_TOKEN" == "your-api-token" ]; then
    echo "Error: CLOUDFLARE_API_TOKEN not set in config.env"
    exit 1
fi

# Delete existing secret if present
kubectl delete secret cloudflare-secrets -n cloudflare-operator-system 2>/dev/null || true

# Determine if using existing tunnel or new tunnel
if [ -n "$CLOUDFLARE_TUNNEL_ID" ] && [ -n "$CLOUDFLARE_TUNNEL_SECRET" ]; then
    echo "Creating secret for EXISTING tunnel..."
    
    CRED_FILE=$(cat <<EOF
{"AccountTag":"${CLOUDFLARE_ACCOUNT_ID}","TunnelID":"${CLOUDFLARE_TUNNEL_ID}","TunnelName":"${CLOUDFLARE_TUNNEL_NAME}","TunnelSecret":"${CLOUDFLARE_TUNNEL_SECRET}"}
EOF
)
    
    kubectl create secret generic cloudflare-secrets \
        --namespace cloudflare-operator-system \
        --from-literal CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN}" \
        --from-literal "CLOUDFLARE_TUNNEL_CREDENTIAL_FILE=${CRED_FILE}"
    
    echo "Secret created with tunnel credentials."
else
    echo "Creating secret for NEW tunnel..."
    
    kubectl create secret generic cloudflare-secrets \
        --namespace cloudflare-operator-system \
        --from-literal CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN}"
    
    echo "Secret created. The operator will create a new tunnel."
fi

echo ""
echo "=== Secret Created ==="
echo ""
echo "Next step: Apply Cloudflare resources:"
echo "  kubectl apply -f manifests/cloudflare/"
