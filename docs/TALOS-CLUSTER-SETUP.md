# Talos Linux Cluster Setup Guide

This document details the complete process of setting up a 3-node Talos Linux cluster on Proxmox with static IP addresses, MetalLB, Traefik, Longhorn, cert-manager, and Cloudflare Tunnel.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Cluster Architecture](#cluster-architecture)
3. [Generating Custom Talos Image](#generating-custom-talos-image)
4. [Creating VMs in Proxmox](#creating-vms-in-proxmox)
5. [Generating Talos Configurations](#generating-talos-configurations)
6. [Applying Configurations](#applying-configurations)
7. [Bootstrapping the Cluster](#bootstrapping-the-cluster)
8. [Installing Core Components](#installing-core-components)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

- Proxmox VE hypervisor(s)
- `talosctl` CLI installed
- `kubectl` CLI installed
- `helm` CLI installed
- Cloudflare account with domain configured
- SSH access to Proxmox hosts

## Cluster Architecture

| Node | Role | IP Address | VM ID | Proxmox Host |
|------|------|------------|-------|--------------|
| talos-cp-01 | Control Plane | 192.168.1.115 | 108 | cumulus |
| talos-worker-01 | Worker | 192.168.1.116 | 110 | cumulus |
| talos-worker-02 | Worker | 192.168.1.151 | 112 | stratus |

### Network Configuration

- **Gateway**: 192.168.1.1
- **DNS**: 8.8.8.8, 1.1.1.1
- **Network Interface**: ens18 (Proxmox virtio)
- **MetalLB IP Pool**: 192.168.1.155-159

---

## Generating Custom Talos Image

Talos requires a custom image with extensions for Longhorn support.

### Step 1: Use Talos Image Factory

Go to [Talos Image Factory](https://factory.talos.dev/) and select:

1. **Talos Version**: v1.11.5
2. **Platform**: nocloud (for Proxmox/QEMU)
3. **Extensions**:
   - `siderolabs/iscsi-tools` (required for Longhorn)
   - `siderolabs/util-linux-tools` (required for Longhorn)

### Step 2: Download the Image

```bash
# Download the custom ISO
wget -O talos-v1.11.5-qemu.iso \
  "https://factory.talos.dev/image/53513e54bb39202f35694412577a6bc53d484744d35a126e5d42ef34785c0d83/v1.11.5/nocloud-amd64.iso"
```

### Step 3: Upload to Proxmox Hosts

```bash
# Upload to Proxmox (repeat for each host)
scp talos-v1.11.5-qemu.iso root@proxmox-host:/var/lib/vz/template/iso/
```

---

## Creating VMs in Proxmox

### VM Specifications

| Setting | Control Plane | Workers |
|---------|---------------|---------|
| Memory | 4096 MB | 8192 MB |
| CPU Cores | 2 | 4 |
| Disk | 50 GB | 100 GB |
| BIOS | OVMF (UEFI) | OVMF (UEFI) |
| Machine | q35 | q35 |

### Creating VMs via CLI

```bash
# Control Plane (VM 108)
qm create 108 \
  --name talos-cp-01 \
  --memory 4096 \
  --cores 2 \
  --cpu host \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci \
  --scsi0 pool:50 \
  --ide2 local:iso/talos-v1.11.5-qemu.iso,media=cdrom \
  --boot order=scsi0\;ide2 \
  --bios ovmf \
  --machine q35 \
  --efidisk0 pool:1,format=raw \
  --agent enabled=1

# Worker 1 (VM 110)
qm create 110 \
  --name talos-worker-01 \
  --memory 8192 \
  --cores 4 \
  --cpu host \
  --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-pci \
  --scsi0 pool:100 \
  --ide2 local:iso/talos-v1.11.5-qemu.iso,media=cdrom \
  --boot order=scsi0\;ide2 \
  --bios ovmf \
  --machine q35 \
  --efidisk0 pool:1,format=raw \
  --agent enabled=1

# Worker 2 (VM 112) - with specific MAC for DHCP reservation
qm create 112 \
  --name talos-worker-02 \
  --memory 8192 \
  --cores 4 \
  --cpu host \
  --net0 virtio,bridge=vmbr0,macaddr=BC:24:11:00:01:18 \
  --scsihw virtio-scsi-pci \
  --scsi0 pool:100 \
  --ide2 local:iso/talos-v1.11.5-qemu.iso,media=cdrom \
  --boot order=scsi0\;ide2 \
  --bios ovmf \
  --machine q35 \
  --efidisk0 pool:1,format=raw \
  --agent enabled=1
```

### MAC Address Management

To ensure consistent IP addresses, you can either:

1. **Set MAC addresses during VM creation** (`macaddr=XX:XX:XX:XX:XX:XX`)
2. **Configure DHCP reservations** on your router for the assigned MACs
3. **Use static IPs in Talos config** (recommended, covered below)

---

## Generating Talos Configurations

### Step 1: Create Patch Files

Each node needs a patch file for static IP configuration and Longhorn support.

**Control Plane Patch** (`controlplane-patch.yaml`):

```yaml
machine:
  network:
    hostname: talos-cp-01
    interfaces:
      - interface: ens18
        addresses:
          - 192.168.1.115/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
    nameservers:
      - 8.8.8.8
      - 1.1.1.1
  install:
    disk: /dev/sda
    image: factory.talos.dev/installer/53513e54bb39202f35694412577a6bc53d484744d35a126e5d42ef34785c0d83:v1.11.5
  kubelet:
    extraMounts:
      - destination: /var/lib/longhorn
        type: bind
        source: /var/lib/longhorn
        options:
          - bind
          - rshared
          - rw
```

**Worker 1 Patch** (`worker1-patch.yaml`):

```yaml
machine:
  network:
    hostname: talos-worker-01
    interfaces:
      - interface: ens18
        addresses:
          - 192.168.1.116/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
    nameservers:
      - 8.8.8.8
      - 1.1.1.1
  install:
    disk: /dev/sda
    image: factory.talos.dev/installer/53513e54bb39202f35694412577a6bc53d484744d35a126e5d42ef34785c0d83:v1.11.5
  kubelet:
    extraMounts:
      - destination: /var/lib/longhorn
        type: bind
        source: /var/lib/longhorn
        options:
          - bind
          - rshared
          - rw
```

**Worker 2 Patch** (`worker2-patch.yaml`):

```yaml
machine:
  network:
    hostname: talos-worker-02
    interfaces:
      - interface: ens18
        addresses:
          - 192.168.1.151/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.1.1
    nameservers:
      - 8.8.8.8
      - 1.1.1.1
  install:
    disk: /dev/sda
    image: factory.talos.dev/installer/53513e54bb39202f35694412577a6bc53d484744d35a126e5d42ef34785c0d83:v1.11.5
  kubelet:
    extraMounts:
      - destination: /var/lib/longhorn
        type: bind
        source: /var/lib/longhorn
        options:
          - bind
          - rshared
          - rw
```

### Step 2: Generate Cluster Configuration

```bash
# Generate configs with control plane patch
talosctl gen config talos-proxmox-cluster https://192.168.1.115:6443 \
  --output-dir _out \
  --kubernetes-version 1.32.0 \
  --config-patch-control-plane @controlplane-patch.yaml \
  --config-patch-worker @worker1-patch.yaml
```

### Step 3: Create Separate Worker 2 Config

**Important**: For workers with different IPs, create a separate config file by copying and modifying:

```bash
# Copy worker.yaml and modify IP
cp _out/worker.yaml _out/worker2-clean.yaml

# Replace IP and hostname
sed -i '' 's/192.168.1.116/192.168.1.151/g' _out/worker2-clean.yaml
sed -i '' 's/talos-worker-01/talos-worker-02/g' _out/worker2-clean.yaml
```

> **Note**: Do NOT regenerate configs for additional workers - this creates new certificates that won't work with the cluster. Always copy and modify the original worker.yaml.

---

## Applying Configurations

### Step 1: Start VMs and Wait for Boot

```bash
# Start VMs
qm start 108
qm start 110
qm start 112

# Wait for VMs to boot (1-2 minutes)
```

### Step 2: Apply Configurations

When VMs boot from ISO, they get temporary DHCP addresses. Apply configs using those addresses:

```bash
export TALOSCONFIG="_out/talosconfig"

# Apply control plane config
talosctl apply-config --insecure --nodes <CP_DHCP_IP> --file _out/controlplane.yaml

# Apply worker 1 config
talosctl apply-config --insecure --nodes <W1_DHCP_IP> --file _out/worker.yaml

# Apply worker 2 config (use the modified file!)
talosctl apply-config --insecure --nodes <W2_DHCP_IP> --file _out/worker2-clean.yaml
```

### Step 3: Wait for Installation

After applying configs, Talos will:
1. Install to disk
2. Reboot
3. Come up on the configured static IP

Wait 2-3 minutes for this process.

---

## Bootstrapping the Cluster

### Step 1: Bootstrap etcd

```bash
export TALOSCONFIG="_out/talosconfig"

# Bootstrap the cluster (run once on control plane)
talosctl bootstrap --nodes 192.168.1.115
```

### Step 2: Generate Kubeconfig

```bash
# Generate kubeconfig
talosctl kubeconfig --nodes 192.168.1.115 ./kubeconfig

# Set environment variable
export KUBECONFIG=$(pwd)/kubeconfig
```

### Step 3: Verify Cluster

```bash
# Check nodes
kubectl get nodes -o wide

# Expected output:
# NAME              STATUS   ROLES           AGE   VERSION   INTERNAL-IP
# talos-cp-01       Ready    control-plane   Xm    v1.32.0   192.168.1.115
# talos-worker-01   Ready    <none>          Xm    v1.32.0   192.168.1.116
# talos-worker-02   Ready    <none>          Xm    v1.32.0   192.168.1.151
```

---

## Installing Core Components

### 1. MetalLB (LoadBalancer)

```bash
# Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

# Wait for pods
kubectl wait --namespace metallb-system \
  --for=condition=ready pod \
  --selector=app=metallb \
  --timeout=90s
```

Create IP address pool (`metallb-config.yaml`):

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.155-192.168.1.159
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
```

```bash
kubectl apply -f metallb-config.yaml
```

### 2. Traefik (Ingress Controller)

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

kubectl create namespace traefik

helm install traefik traefik/traefik \
  --namespace traefik \
  --set ports.web.exposedPort=80 \
  --set ports.websecure.exposedPort=443 \
  --set service.type=LoadBalancer
```

### 3. Longhorn (Storage)

```bash
# Create namespace with PSP labels
kubectl create namespace longhorn-system
kubectl label namespace longhorn-system \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged

# Install Longhorn
helm repo add longhorn https://charts.longhorn.io
helm repo update

helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --set defaultSettings.defaultDataPath="/var/lib/longhorn" \
  --set persistence.defaultClass=true \
  --set persistence.defaultClassReplicaCount=2
```

### 4. cert-manager (SSL Certificates)

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.1/cert-manager.yaml

# Wait for pods
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=90s
```

Create Cloudflare DNS issuer (see [CLOUDFLARE-TUNNEL-SETUP.md](./CLOUDFLARE-TUNNEL-SETUP.md) for details).

---

## Troubleshooting

### Common Issues

#### 1. Duplicate IP Addresses on Workers

**Problem**: Worker nodes have multiple IP addresses configured.

**Cause**: Using `--config-patch` when applying configs adds to existing network config instead of replacing.

**Solution**: Create a separate config file by copying and using `sed` to replace IPs:

```bash
cp _out/worker.yaml _out/worker2-clean.yaml
sed -i '' 's/192.168.1.116/192.168.1.151/g' _out/worker2-clean.yaml
```

#### 2. Certificate Errors When Joining Cluster

**Problem**: New workers fail with "certificate signed by unknown authority".

**Cause**: Generated new configs with `talosctl gen config` which creates new certificates.

**Solution**: Always copy the original worker.yaml and modify only the IP/hostname.

#### 3. Interface Name Wrong

**Problem**: Network not working after applying config.

**Cause**: Using `eth0` instead of `ens18` (Proxmox uses `ens18` for virtio NICs).

**Solution**: Check interface name with `talosctl get links --nodes <IP>` and use correct name in patches.

#### 4. Node Stuck in "Booting" State

**Problem**: Talos console shows "Booting" but never becomes Ready.

**Cause**: Usually etcd issues or network connectivity problems.

**Solution**:
```bash
# Check Talos status
talosctl --nodes <IP> dashboard

# Check logs
talosctl --nodes <IP> logs controller-runtime
```

### Useful Commands

```bash
# Check node status
talosctl --nodes 192.168.1.115 get members

# Check network addresses
talosctl --nodes 192.168.1.115 get addresses

# View Talos dashboard
talosctl --nodes 192.168.1.115 dashboard

# Reset a node (wipes everything!)
talosctl --nodes <IP> reset --graceful=false --reboot

# Check kubelet logs
talosctl --nodes <IP> logs kubelet
```

---

## Next Steps

After completing this setup, proceed to:

1. [Cloudflare Tunnel Setup](./CLOUDFLARE-TUNNEL-SETUP.md) - Expose services securely
2. [Ghost Blog Deployment](./GHOST-DEPLOYMENT.md) - Deploy Ghost CMS
