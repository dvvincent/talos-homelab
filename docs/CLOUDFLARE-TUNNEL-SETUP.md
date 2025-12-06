# Cloudflare Tunnel Setup with cloudflare-operator

This document details the complete process of setting up Cloudflare Tunnel using the cloudflare-operator on a Kubernetes cluster.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Creating Cloudflare API Token](#creating-cloudflare-api-token)
4. [Installing cloudflare-operator](#installing-cloudflare-operator)
5. [Creating the Tunnel Secret](#creating-the-tunnel-secret)
6. [Creating ClusterTunnel Resource](#creating-clustertunnel-resource)
7. [Creating TunnelBinding Resources](#creating-tunnelbinding-resources)
8. [Configuring Geo-Blocking](#configuring-geo-blocking)
9. [Configuring Cloudflare Access](#configuring-cloudflare-access)
10. [Troubleshooting](#troubleshooting)

---

## Prerequisites

- Kubernetes cluster (Talos Linux, k3s, etc.)
- Cloudflare account with a domain
- Domain's nameservers pointed to Cloudflare
- `kubectl` and `helm` installed

## Architecture Overview

```
                                    ┌──────────────────┐
                                    │   Cloudflare     │
                                    │   Edge Network   │
                                    └────────┬─────────┘
                                             │
                                             │ HTTPS
                                             │
┌────────────────────────────────────────────┼───────────────────────────────────┐
│  Kubernetes Cluster                        │                                   │
│                                            │                                   │
│  ┌─────────────────────────────────────────┼─────────────────────────────────┐ │
│  │ cloudflare-operator-system              │                                 │ │
│  │                                         │                                 │ │
│  │  ┌──────────────────┐    ┌──────────────▼───────────┐                     │ │
│  │  │ cloudflare-      │    │  cloudflared pods (x2)   │                     │ │
│  │  │ operator         │───►│  (homelab-tunnel)      │                     │ │
│  │  └──────────────────┘    └──────────────┬───────────┘                     │ │
│  │                                         │                                 │ │
│  └─────────────────────────────────────────┼─────────────────────────────────┘ │
│                                            │                                   │
│  ┌─────────────────────────────────────────┼─────────────────────────────────┐ │
│  │ ghost namespace                         │                                 │ │
│  │                                         │                                 │ │
│  │  ┌──────────────────┐    ┌──────────────▼───────────┐                     │ │
│  │  │ TunnelBinding    │───►│  Ghost Service           │                     │ │
│  │  │ (ghost-binding)  │    │  (ghost:2368)            │                     │ │
│  │  └──────────────────┘    └──────────────────────────┘                     │ │
│  │                                                                           │ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
│                                                                                │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

## Creating Cloudflare API Token

### Required Permissions

Create an API token at [Cloudflare Dashboard > Profile > API Tokens](https://dash.cloudflare.com/profile/api-tokens) with:

| Permission | Access Level |
|------------|--------------|
| Account > Cloudflare Tunnel | Edit |
| Account > Account Settings | Read |
| Zone > DNS | Edit |

### Token Configuration

1. Go to **My Profile** → **API Tokens** → **Create Token**
2. Select **Create Custom Token**
3. Configure permissions as shown above
4. Set **Account Resources**: Include → Your Account
5. Set **Zone Resources**: Include → Your Zone (e.g., `yourdomain.com`)
6. Create and **save the token** - you won't see it again!

---

## Installing cloudflare-operator

### Installation

```bash
# Install the operator (use specific version for stability)
kubectl apply -k 'https://github.com/adyanth/cloudflare-operator.git/config/default?ref=v0.13.1'

# Wait for operator to be ready
kubectl wait --namespace cloudflare-operator-system \
  --for=condition=ready pod \
  --selector=control-plane=controller-manager \
  --timeout=120s
```

### Verify Installation

```bash
kubectl get pods -n cloudflare-operator-system
# Should show controller-manager running
```

---

## Creating the Tunnel Secret

The secret configuration depends on whether you're creating a **new tunnel** or using an **existing tunnel**.

### Option A: New Tunnel (Recommended for fresh setups)

Only the API token is needed:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cloudflare-secrets
  namespace: cloudflare-operator-system
type: Opaque
stringData:
  CLOUDFLARE_API_TOKEN: "<your-api-token>"
```

```bash
kubectl create secret generic cloudflare-secrets \
  --namespace cloudflare-operator-system \
  --from-literal CLOUDFLARE_API_TOKEN=<your-api-token>
```

### Option B: Existing Tunnel

If you already created a tunnel via API/CLI, you need **both** the API token and tunnel credentials:

```bash
kubectl create secret generic cloudflare-secrets \
  --namespace cloudflare-operator-system \
  --from-literal CLOUDFLARE_API_TOKEN=<your-api-token> \
  --from-literal 'CLOUDFLARE_TUNNEL_CREDENTIAL_FILE={"AccountTag":"<account-id>","TunnelID":"<tunnel-id>","TunnelName":"<tunnel-name>","TunnelSecret":"<tunnel-secret>"}'
```

**Example with real values:**

```bash
kubectl create secret generic cloudflare-secrets \
  --namespace cloudflare-operator-system \
  --from-literal CLOUDFLARE_API_TOKEN=<your-api-token> \
  --from-literal 'CLOUDFLARE_TUNNEL_CREDENTIAL_FILE={"AccountTag":"<your-account-id>","TunnelID":"<your-tunnel-id>","TunnelName":"your-tunnel-name","TunnelSecret":"<your-tunnel-secret>"}'
```

---

## Creating ClusterTunnel Resource

### Option A: New Tunnel

```yaml
apiVersion: networking.cfargotunnel.com/v1alpha1
kind: ClusterTunnel
metadata:
  name: my-tunnel
spec:
  cloudflare:
    accountId: "<your-account-id>"
    domain: "<your-domain>"
    secret: "cloudflare-secrets"
  image: "cloudflare/cloudflared:latest"
  newTunnel:
    name: "my-k8s-tunnel"
  size: 2  # Number of cloudflared replicas
```

### Option B: Existing Tunnel

```yaml
apiVersion: networking.cfargotunnel.com/v1alpha1
kind: ClusterTunnel
metadata:
  name: homelab-tunnel
spec:
  cloudflare:
    accountId: "<your-account-id>"
    domain: "yourdomain.com"
    secret: "cloudflare-secrets"
  image: "cloudflare/cloudflared:latest"
  existingTunnel:
    id: "<your-tunnel-id>"
    name: "your-tunnel-name"
  size: 2
```

### Apply and Verify

```bash
kubectl apply -f clustertunnel.yaml

# Check tunnel status
kubectl get clustertunnel
# NAME               TUNNELID
# homelab-tunnel   <your-tunnel-id>

# Check cloudflared pods
kubectl get pods -n cloudflare-operator-system | grep tunnel
# homelab-tunnel-xxx   1/1     Running   0          1m
# homelab-tunnel-xxx   1/1     Running   0          1m
```

---

## Creating TunnelBinding Resources

TunnelBindings define which services should be exposed through the tunnel.

### Basic TunnelBinding

```yaml
apiVersion: networking.cfargotunnel.com/v1alpha1
kind: TunnelBinding
metadata:
  name: ghost-binding
  namespace: ghost  # Must be in same namespace as the service
subjects:
  - kind: Service
    name: ghost
    spec:
      fqdn: yourdomain.com
      protocol: http
      target: http://ghost.ghost.svc.cluster.local:2368
  - kind: Service
    name: ghost
    spec:
      fqdn: www.yourdomain.com
      protocol: http
      target: http://ghost.ghost.svc.cluster.local:2368
tunnelRef:
  kind: ClusterTunnel
  name: homelab-tunnel
```

### Apply and Verify

```bash
kubectl apply -f tunnelbinding.yaml

# Check binding status
kubectl get tunnelbinding -n ghost
# NAME            FQDNS
# ghost-binding   yourdomain.com,www.yourdomain.com
```

---

## Configuring Geo-Blocking

Block traffic from high-risk countries using Cloudflare WAF.

### Via Cloudflare Dashboard

1. Go to **Security** → **WAF** → **Create Rule**
2. Configure:
   - **Name**: Block Tier 1 and Tier 2 Countries
   - **Expression**: 
     ```
     (ip.geoip.country in {"KP" "IR" "SY" "CU" "SD" "RU" "BY" "CN" "VE" "MM" "LY" "SO" "YE" "AF" "IQ"})
     ```
   - **Action**: Block

### Via API

```bash
curl -X POST "https://api.cloudflare.com/client/v4/zones/<zone-id>/firewall/rules" \
  -H "X-Auth-Email: <email>" \
  -H "X-Auth-Key: <api-key>" \
  -H "Content-Type: application/json" \
  --data '[{
    "filter": {
      "expression": "(ip.geoip.country in {\"KP\" \"IR\" \"SY\" \"CU\" \"SD\" \"RU\" \"BY\" \"CN\" \"VE\" \"MM\" \"LY\" \"SO\" \"YE\" \"AF\" \"IQ\"})",
      "paused": false,
      "description": "Block Tier 1 and Tier 2 Unsafe Countries"
    },
    "action": "block",
    "priority": 1,
    "description": "Block Tier 1 and Tier 2 Unsafe Countries"
  }]'
```

### Countries Blocked

| Tier | Countries |
|------|-----------|
| Tier 1 (High Risk) | North Korea (KP), Iran (IR), Syria (SY), Cuba (CU), Sudan (SD) |
| Tier 2 (Elevated Risk) | Russia (RU), Belarus (BY), China (CN), Venezuela (VE), Myanmar (MM), Libya (LY), Somalia (SO), Yemen (YE), Afghanistan (AF), Iraq (IQ) |

---

## Configuring Cloudflare Access

Protect your application with Cloudflare Access for authentication.

### Via API

```bash
# Create Access Application
curl -X POST "https://api.cloudflare.com/client/v4/accounts/<account-id>/access/apps" \
  -H "X-Auth-Email: <email>" \
  -H "X-Auth-Key: <api-key>" \
  -H "Content-Type: application/json" \
  --data '{
    "name": "NexusLabs Blog",
    "domain": "yourdomain.com",
    "self_hosted_domains": ["yourdomain.com", "www.yourdomain.com"],
    "type": "self_hosted",
    "session_duration": "24h"
  }'

# Create Access Policy (allow specific email)
curl -X POST "https://api.cloudflare.com/client/v4/accounts/<account-id>/access/apps/<app-id>/policies" \
  -H "X-Auth-Email: <email>" \
  -H "X-Auth-Key: <api-key>" \
  -H "Content-Type: application/json" \
  --data '{
    "name": "Allow Owner",
    "decision": "allow",
    "include": [{"email": {"email": "your-email@example.com"}}],
    "precedence": 1
  }'
```

### Via Dashboard

1. Go to **Cloudflare Zero Trust** → **Access** → **Applications**
2. Click **Add an application** → **Self-hosted**
3. Configure:
   - **Application name**: Your App Name
   - **Session Duration**: 24 hours
   - **Application domain**: your-domain.com
4. Add policy to allow specific emails or domains

---

## Troubleshooting

### Common Issues

#### 1. "Neither Key found in Secret"

**Cause**: Secret doesn't have the expected keys.

**Solution**: Ensure secret has `CLOUDFLARE_API_TOKEN`. For existing tunnels, also add `CLOUDFLARE_TUNNEL_CREDENTIAL_FILE`.

```bash
# Check secret keys
kubectl get secret cloudflare-secrets -n cloudflare-operator-system -o yaml
```

#### 2. "Error validating Cloudflare API credentials"

**Cause**: API token missing required permissions.

**Solution**: Ensure token has:
- Account > Cloudflare Tunnel > Edit
- Account > Account Settings > Read
- Zone > DNS > Edit

#### 3. "You already have a tunnel with this name"

**Cause**: Trying to create a new tunnel with a name that already exists.

**Solution**: Either:
- Delete the existing tunnel in Cloudflare Dashboard
- Use `existingTunnel` instead of `newTunnel` (requires tunnel credentials)

#### 4. "Error finding ConfigMap for Tunnel"

**Cause**: TunnelBinding created before ClusterTunnel was ready.

**Solution**: Delete and recreate the TunnelBinding after ClusterTunnel shows a TUNNELID.

```bash
kubectl delete tunnelbinding <name> -n <namespace>
kubectl apply -f tunnelbinding.yaml
```

### Useful Commands

```bash
# Check operator logs
kubectl logs -n cloudflare-operator-system deployment/cloudflare-operator-controller-manager

# Check tunnel status
kubectl describe clustertunnel <name>

# Check binding status
kubectl describe tunnelbinding <name> -n <namespace>

# Check cloudflared logs
kubectl logs -n cloudflare-operator-system -l cfargotunnel.com/tunnel=<tunnel-name>

# Restart operator
kubectl delete pod -n cloudflare-operator-system -l control-plane=controller-manager
```

---

## Complete Example Files

See the following files in this repository:

- `cloudflare-tunnel-operator.yaml` - ClusterTunnel and TunnelBinding
- `cloudflare-credentials.env` - API credentials (git-ignored)
- `cert-manager-clusterissuer.yaml` - Let's Encrypt issuer with Cloudflare DNS

---

## Next Steps

1. Test access to your application via the tunnel
2. Set up SSL certificates with cert-manager
3. Configure additional TunnelBindings for other services
