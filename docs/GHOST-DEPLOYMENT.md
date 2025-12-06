# Ghost Blog Deployment Guide

This document details deploying Ghost CMS on Kubernetes with persistent storage and Cloudflare Tunnel access.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Ghost Deployment](#ghost-deployment)
3. [Persistent Storage](#persistent-storage)
4. [Ingress Configuration](#ingress-configuration)
5. [SSL Certificates](#ssl-certificates)
6. [Cloudflare Tunnel Integration](#cloudflare-tunnel-integration)
7. [Accessing Ghost Admin](#accessing-ghost-admin)
8. [Backup and Restore](#backup-and-restore)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

- Kubernetes cluster with:
  - Longhorn storage class
  - cert-manager installed
  - Traefik or other ingress controller
  - Cloudflare Tunnel configured
- Domain pointed to Cloudflare

---

## Ghost Deployment

### Complete Deployment

Create `ghost-deployment.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ghost
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ghost-content
  namespace: ghost
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ghost-config
  namespace: ghost
data:
  url: "https://yourdomain.com"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ghost
  namespace: ghost
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ghost
  template:
    metadata:
      labels:
        app: ghost
    spec:
      containers:
      - name: ghost
        image: ghost:5-alpine
        ports:
        - containerPort: 2368
          name: http
        env:
        - name: url
          valueFrom:
            configMapKeyRef:
              name: ghost-config
              key: url
        - name: NODE_ENV
          value: production
        - name: database__client
          value: sqlite3
        - name: database__connection__filename
          value: /var/lib/ghost/content/data/ghost.db
        volumeMounts:
        - name: ghost-content
          mountPath: /var/lib/ghost/content
      volumes:
      - name: ghost-content
        persistentVolumeClaim:
          claimName: ghost-content
---
apiVersion: v1
kind: Service
metadata:
  name: ghost
  namespace: ghost
spec:
  selector:
    app: ghost
  ports:
  - port: 2368
    targetPort: 2368
    name: http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ghost
  namespace: ghost
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  ingressClassName: traefik
  tls:
  - hosts:
    - yourdomain.com
    - www.yourdomain.com
    secretName: wildcard-tls
  rules:
  - host: yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ghost
            port:
              number: 2368
  - host: www.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ghost
            port:
              number: 2368
```

### Deploy

```bash
kubectl apply -f ghost-deployment.yaml
```

### Verify Deployment

```bash
# Check pods
kubectl get pods -n ghost

# Check PVC
kubectl get pvc -n ghost

# Check service
kubectl get svc -n ghost

# Check ingress
kubectl get ingress -n ghost

# Check logs
kubectl logs -n ghost deployment/ghost
```

---

## Persistent Storage

Ghost uses SQLite by default with the configuration above. All content is stored in the PVC.

### Storage Details

| Path | Contents |
|------|----------|
| `/var/lib/ghost/content/data/` | SQLite database (`ghost.db`) |
| `/var/lib/ghost/content/images/` | Uploaded images |
| `/var/lib/ghost/content/themes/` | Custom themes |
| `/var/lib/ghost/content/files/` | File uploads |

### Checking Storage Usage

```bash
# Get pod name
POD=$(kubectl get pod -n ghost -l app=ghost -o jsonpath='{.items[0].metadata.name}')

# Check disk usage
kubectl exec -n ghost $POD -- du -sh /var/lib/ghost/content/*
```

---

## SSL Certificates

### Wildcard Certificate

A wildcard certificate (`*.yourdomain.com`) is created using cert-manager with Cloudflare DNS validation.

**Certificate resource** (`wildcard-cert.yaml`):

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard
  namespace: default
spec:
  secretName: wildcard-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - '*.yourdomain.com'
  - 'yourdomain.com'
```

### Check Certificate Status

```bash
kubectl get certificate -n default
kubectl describe certificate wildcard -n default
```

---

## Cloudflare Tunnel Integration

Ghost is exposed via Cloudflare Tunnel using the cloudflare-operator.

### TunnelBinding

```yaml
apiVersion: networking.cfargotunnel.com/v1alpha1
kind: TunnelBinding
metadata:
  name: ghost-binding
  namespace: ghost
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

### Verify Tunnel Binding

```bash
kubectl get tunnelbinding -n ghost
# NAME            FQDNS
# ghost-binding   yourdomain.com,www.yourdomain.com
```

---

## Accessing Ghost Admin

### Initial Setup

1. Navigate to `https://yourdomain.com/ghost`
2. If Cloudflare Access is enabled, authenticate with your email
3. Create your admin account
4. Configure your blog settings

### Admin URLs

| URL | Description |
|-----|-------------|
| `https://yourdomain.com/` | Public blog |
| `https://yourdomain.com/ghost/` | Admin dashboard |
| `https://yourdomain.com/ghost/#/settings` | Settings |
| `https://yourdomain.com/ghost/#/posts` | Posts management |

---

## Backup and Restore

### Manual Backup

```bash
# Get pod name
POD=$(kubectl get pod -n ghost -l app=ghost -o jsonpath='{.items[0].metadata.name}')

# Create backup directory
mkdir -p ghost-backup

# Copy content
kubectl cp ghost/$POD:/var/lib/ghost/content ./ghost-backup/content
```

### Restore from Backup

```bash
# Scale down Ghost
kubectl scale deployment ghost -n ghost --replicas=0

# Copy content back
kubectl cp ./ghost-backup/content ghost/$POD:/var/lib/ghost/content

# Scale up
kubectl scale deployment ghost -n ghost --replicas=1
```

### Using Longhorn Snapshots

```bash
# Create snapshot via Longhorn UI
# Access at: http://<node-ip>:30880

# Or via kubectl
kubectl get volumes.longhorn.io -n longhorn-system
```

---

## Troubleshooting

### Common Issues

#### 1. Ghost Crashes with Database Error

**Problem**: Ghost fails with "connect ECONNREFUSED 127.0.0.1:3306"

**Cause**: Ghost defaults to MySQL but no MySQL is deployed.

**Solution**: Configure SQLite in environment variables:

```yaml
env:
- name: database__client
  value: sqlite3
- name: database__connection__filename
  value: /var/lib/ghost/content/data/ghost.db
```

#### 2. PVC Stuck in Pending

**Problem**: PersistentVolumeClaim won't bind.

**Cause**: Longhorn not ready or no available nodes.

**Solution**:
```bash
# Check Longhorn status
kubectl get pods -n longhorn-system

# Check PVC events
kubectl describe pvc ghost-content -n ghost
```

#### 3. Ghost Pod CrashLoopBackOff

**Problem**: Pod keeps restarting.

**Solution**:
```bash
# Check logs
kubectl logs -n ghost deployment/ghost --previous

# Common causes:
# - Wrong URL configuration
# - Database issues
# - Permission problems
```

#### 4. Can't Access Ghost Admin

**Problem**: 404 or connection refused.

**Cause**: Tunnel not configured correctly.

**Solution**:
```bash
# Check TunnelBinding
kubectl describe tunnelbinding ghost-binding -n ghost

# Check cloudflared logs
kubectl logs -n cloudflare-operator-system -l cfargotunnel.com/tunnel=homelab-tunnel
```

### Useful Commands

```bash
# View Ghost logs
kubectl logs -n ghost deployment/ghost -f

# Restart Ghost
kubectl rollout restart deployment ghost -n ghost

# Get Ghost shell
kubectl exec -it -n ghost deployment/ghost -- sh

# Check Ghost status
kubectl describe deployment ghost -n ghost
```

---

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `url` | Public URL of your blog | Required |
| `NODE_ENV` | Node environment | production |
| `database__client` | Database type | mysql |
| `database__connection__filename` | SQLite db path | N/A |

---

## Production Recommendations

1. **Use MySQL/MariaDB** for production instead of SQLite
2. **Configure email** (Mailgun, SendGrid) for newsletters
3. **Set up Redis** for caching
4. **Enable CDN** in Cloudflare for images
5. **Regular backups** using Longhorn snapshots
6. **Monitor** with Prometheus/Grafana
