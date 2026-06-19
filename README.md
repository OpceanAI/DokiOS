# Dokios

Dokios is a custom Alpine Linux-based distribution optimized for container workloads. It serves as the operating system layer for the [Doki](https://github.com/OpceanAI/Doki) container engine.

## Overview

Dokios provides:

- **Optimized kernel** with container-specific features enabled
- **Pre-configured container runtime** with Doki engine
- **Minimal footprint** for fast boot times and low resource usage
- **Multiple deployment targets**: VMs (QEMU, Virtualization.framework), bare metal, containers

## Repository Structure

```
Dokios/
├── main/              # Alpine main repository (1,660 packages)
├── community/         # Alpine community repository (7,812 packages)
├── testing/           # Alpine testing repository (3,156 packages)
├── doki/              # Doki-specific packages
│   ├── doki/          # Container engine CLI
│   ├── dokid/         # Container engine daemon
│   ├── doki-compose/  # Compose implementation
│   ├── doki-init/     # PID 1 init system
│   ├── doki-kube/     # Kubernetes components
│   ├── doki-kubectl/  # kubectl-compatible CLI
│   ├── doki-os-base/  # Base metapackage
│   ├── doki-os-kernel/# Custom container-optimized kernel
│   └── doki-os-vm/    # VM metapackage
├── scripts/           # Image building scripts
├── overlay/           # Custom configuration overlays
└── profiles/          # Image profiles
```

## Doki Packages

### Core Components

| Package | Description |
|---------|-------------|
| `doki` | Container engine CLI (Docker-compatible) |
| `dokid` | Container engine daemon with Docker API + Podman API |
| `doki-compose` | Multi-container orchestration |
| `doki-init` | Minimal init system for containers and VMs |

### Kubernetes Support

| Package | Description |
|---------|-------------|
| `doki-kube` | Kubernetes control plane components |
| `doki-kubectl` | kubectl-compatible command-line tool |

### System Packages

| Package | Description |
|---------|-------------|
| `doki-os-base` | Metapackage for base system |
| `doki-os-kernel` | Custom Linux kernel optimized for containers |
| `doki-os-vm` | Metapackage for VM deployments |

## Kernel Features

The `doki-os-kernel` is based on Alpine's `linux-virt` with additional optimizations:

### Container Features
- All namespace types (PID, network, mount, user, UTS, IPC, cgroup)
- Cgroups v2 with full controller support
- OverlayFS with metacopy and redirect_dir
- Seccomp-BPF filtering
- Landlock LSM (unprivileged security)

### Virtualization
- Virtio devices (blk, net, fs, console, balloon)
- 9P filesystem for host-guest sharing
- vsock for VM-host communication
- KVM support for nested virtualization

### Networking
- Bridge networking
- VLAN support
- nftables firewall
- WiFi support (for package downloads)
- VXLAN, Geneve, MACVLAN, IPVLAN

### Security
- SELinux support
- AppArmor support
- Landlock (unprivileged sandboxing)
- fs-verity for integrity verification

## Building Images

### Prerequisites

Install required tools on Alpine:

```bash
apk add abuild apk-tools alpine-conf busybox fakeroot \
    syslinux xorriso grub mtools sfdisk dosfstools \
    squashfs-tools go
```

### Build Doki Packages

```bash
# Build all doki packages
for pkg in doki dokid doki-compose doki-init doki-kube doki-kubectl doki-os-base doki-os-kernel doki-os-vm; do
    cd doki/$pkg
    abuild -r
    cd ../..
done
```

### Build Images

#### Initramfs Image (for VMs)

Creates a minimal initramfs with all components in RAM:

```bash
./scripts/mkimage.sh \
    --arch aarch64 \
    --profile doki_os_initramfs \
    --repository ./packages/aarch64 \
    --repository https://dl-cdn.alpinelinux.org/alpine/edge/main \
    --repository https://dl-cdn.alpinelinux.org/alpine/edge/community \
    --outdir output/ \
    --tag 0.10.0
```

Output:
- `doki-os-initramfs-aarch64.tar.gz` - Root filesystem
- `vmlinuz-doki-os` - Kernel

#### QCOW2 Image (for persistent VMs)

Creates a disk image with persistent storage:

```bash
./scripts/mkimage.sh \
    --arch aarch64 \
    --profile doki_os_vm \
    --repository ./packages/aarch64 \
    --repository https://dl-cdn.alpinelinux.org/alpine/edge/main \
    --repository https://dl-cdn.alpinelinux.org/alpine/edge/community \
    --outdir output/ \
    --tag 0.10.0
```

Output:
- `doki-os-vm-aarch64.img.gz` - Compressed disk image

#### Mini Rootfs (for containers)

Creates a minimal rootfs for running Dokios inside containers:

```bash
./scripts/mkimage.sh \
    --arch aarch64 \
    --profile doki_os_minirootfs \
    --repository ./packages/aarch64 \
    --repository https://dl-cdn.alpinelinux.org/alpine/edge/main \
    --repository https://dl-cdn.alpinelinux.org/alpine/edge/community \
    --outdir output/ \
    --tag 0.10.0
```

Output:
- `doki-os-minirootfs-aarch64.tar.gz` - Minimal rootfs

## Running Dokios

### In QEMU (aarch64)

```bash
qemu-system-aarch64 \
    -M virt \
    -cpu cortex-a57 \
    -m 1G \
    -kernel vmlinuz-doki-os \
    -initrd doki-os-initramfs-aarch64.tar.gz \
    -append "console=ttyAMA0" \
    -nographic \
    -netdev user,id=net0 \
    -device virtio-net-device,netdev=net0
```

### In QEMU with Disk (aarch64)

```bash
# Extract disk image
gunzip doki-os-vm-aarch64.img.gz

qemu-system-aarch64 \
    -M virt \
    -cpu cortex-a57 \
    -m 2G \
    -kernel vmlinuz-doki-os \
    -initrd doki-os-initramfs-aarch64.tar.gz \
    -append "console=ttyAMA0 root=/dev/vda" \
    -drive file=doki-os-vm-aarch64.img,format=raw,if=virtio \
    -nographic \
    -netdev user,id=net0 \
    -device virtio-net-device,netdev=net0
```

### On macOS with Virtualization.framework

```bash
# Using tart or similar VZ-based VM tools
tart create --from-ipsw latest
tart run --kernel vmlinuz-doki-os --initrd doki-os-initramfs-aarch64.tar.gz
```

### As a Container

```bash
# Run Dokios inside Docker/Podman
docker run --privileged -it doki/doki-os:latest /bin/sh
```

## Configuration

### Doki Daemon Configuration

Edit `/etc/doki/config.json`:

```json
{
    "storage_driver": "overlay2",
    "default_network": "bridge",
    "dns": {
        "listen": "127.0.0.11:53"
    },
    "log_level": "info"
}
```

### Network Configuration

Edit `/etc/network/interfaces`:

```
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
```

### WiFi Configuration

Edit `/etc/wpa_supplicant/wpa_supplicant.conf`:

```
ctrl_interface=/var/run/wpa_supplicant
update_config=1

network={
    ssid="YourNetwork"
    psk="YourPassword"
}
```

## Package Management

Dokios uses Alpine's `apk` package manager:

```bash
# Update package index
apk update

# Install a package
apk add nginx

# Search for packages
apk search python3

# Remove a package
apk del nginx
```

### Adding Doki Repository

The Doki repository is pre-configured in `/etc/apk/repositories.d/doki.list`:

```
https://github.com/OpceanAI/DokiOS/releases/download/packages/edge/doki
```

## Documentation

- [DOKI-OS.md](DOKI-OS.md) - Detailed doki-OS documentation
- [CODINGSTYLE.md](CODINGSTYLE.md) - APKBUILD coding style guide
- [COMMITSTYLE.md](COMMITSTYLE.md) - Commit message conventions

## License

- Alpine Linux packages: Various (see individual packages)
- Doki packages: GPL-3.0 (due to BusyBox integration)
- Custom kernel config: GPL-2.0

## Links

- [Doki Container Engine](https://github.com/OpceanAI/Doki)
- [Alpine Linux](https://alpinelinux.org/)
- [Documentation](https://doki.opceanai.com/docs/dokios)
