# Talos Homelab Kubernetes Cluster

A production-ready Kubernetes homelab running Talos Linux with Cloudflare Tunnel for secure, zero-port-forward access.

## 🏗️ Architecture

```
                            INTERNET
                                │
                    ┌───────────▼───────────┐
                    │      CLOUDFLARE       │
                    │  WAF │ DDoS │ Access  │
                    │         │             │
                    │    ┌────▼────┐        │
                    │    │ Tunnel  │        │
                    └────┴────│────┴────────┘
                              │
            ┌─────────────────│─────────────────┐
            │     HOMELAB (No open ports!)      │
            │                 │                  │
            │    ┌────────────▼────────────┐    │
            │    │    Kubernetes Cluster   │    │
            │    │  talos-cp │ worker × 2  │    │
            │    └─────────────────────────┘    │
            └───────────────────────────────────┘
```

## 📦 Components

| Component | Version | Purpose |
|-----------|---------|---------|
| Talos Linux | v1.11.5 | Immutable Kubernetes OS |
| Kubernetes | v1.32.0 | Container orchestration |
| MetalLB | v0.14.9 | LoadBalancer for bare metal |
| Traefik | v3.6.2 | Ingress controller |
| Longhorn | latest | Distributed block storage |
| cert-manager | v1.19.1 | Automatic SSL certificates |
| cloudflare-operator | v0.13.1 | Cloudflare Tunnel management |

## 🚀 Quick Start

### Prerequisites

- Proxmox VE or other hypervisor
- Cloudflare account with a domain
- `talosctl`, `kubectl`, and `helm` installed

### 1. Generate Talos Image

Download the custom Talos image with Longhorn extensions from [Talos Image Factory](https://factory.talos.dev):

```bash
wget -O talos-v1.11.5-qemu.iso \
  "https://factory.talos.dev/image/53513e54bb39202f35694412577a6bc53d484744d35a126e5d42ef34785c0d83/v1.11.5/nocloud-amd64.iso"
```

### 2. Create VMs

Create 3 VMs in Proxmox using the scripts in `talos/scripts/`.

### 3. Configure and Deploy

```bash
# Copy and edit configuration
cp config.example.env config.env
# Edit config.env with your values

# Run pre-flight checks
./preflight.sh

# Generate Talos configs
./talos/scripts/generate-configs.sh

# Apply configurations
./talos/scripts/apply-configs.sh

# Bootstrap cluster
./talos/scripts/bootstrap.sh

# Install core components
./deploy.sh
```

### 4. Set Up Cloudflare Tunnel

```bash
# Create Cloudflare secret
./talos/scripts/create-cloudflare-secret.sh

# Deploy tunnel
kubectl apply -f manifests/cloudflare/
```

## 📁 Repository Structure

```
├── README.md
├── BLOG.md                    # Detailed blog post about the build
├── config.example.env         # Example configuration
├── preflight.sh               # Pre-flight checks script
├── deploy.sh                  # Main deployment script
├── docs/
│   ├── TALOS-CLUSTER-SETUP.md
│   ├── CLOUDFLARE-TUNNEL-SETUP.md
│   └── GHOST-DEPLOYMENT.md
├── manifests/
│   ├── core/
│   │   ├── metallb-config.yaml
│   │   ├── cert-manager-issuer.yaml
│   │   └── wildcard-certificate.yaml
│   ├── apps/
│   │   └── ghost/
│   │       └── ghost-deployment.yaml
│   └── cloudflare/
│       ├── clustertunnel.yaml
│       └── tunnelbindings.yaml
└── talos/
    ├── patches/
    │   ├── controlplane-patch.yaml
    │   ├── worker1-patch.yaml
    │   └── worker2-patch.yaml
    └── scripts/
        ├── generate-configs.sh
        ├── apply-configs.sh
        └── bootstrap.sh
```

## 🔐 Security Features

- ✅ **Zero exposed ports** - All traffic through Cloudflare Tunnel
- ✅ **Geo-blocking** - Tier 1 & 2 threat countries blocked
- ✅ **Cloudflare Access** - Email-based authentication
- ✅ **DDoS protection** - Cloudflare edge network
- ✅ **Automatic SSL** - Let's Encrypt wildcard certificates

## 📖 Documentation

- [Talos Cluster Setup Guide](docs/TALOS-CLUSTER-SETUP.md)
- [Cloudflare Tunnel Setup](docs/CLOUDFLARE-TUNNEL-SETUP.md)
- [Ghost Blog Deployment](docs/GHOST-DEPLOYMENT.md)
- [Full Blog Post](BLOG.md)

## 🤝 Contributing

Contributions welcome! Please read the documentation before submitting PRs.

## 📄 License

MIT License - See [LICENSE](LICENSE) for details.
