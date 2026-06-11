# doki-OS

Container-optimized operating system based on Alpine Linux, purpose-built for the [Doki](https://github.com/OpceanAI/Doki) container engine.

## Overview

doki-OS is not a general-purpose distribution. It is a minimal, immutable, container-first OS designed to run as:

- **VM guest** on macOS (Virtualization.framework, QEMU)
- **VM guest** on Linux (Firecracker, crosvm, QEMU)
- **VM guest** on Android (QEMU via Termux)
- **Container image** for testing and CI

## Features

| Feature | Detail |
|---|---|
| **Kernel** | Linux 7.0+ custom-configured for containers |
| **Init** | doki-init (Go, PID 1, zombie reaping, signal forwarding) |
| **Container Engine** | Doki pre-installed (Docker API v1.54 + Podman libpod v5) |
| **APK** | Full Alpine package manager (add/remove/upgrade packages) |
| **WiFi** | Built-in WiFi support for downloading packages |
| **Size** | ~18MB compressed (qcow2), ~25MB (initramfs) |
| **Boot time** | <3 seconds |
| **License** | MIT (Alpine base) + Apache 2.0 (Doki components) |

## Image Types

### initramfs (no disk)

Everything runs in RAM. No persistent storage. Ideal for ephemeral workloads.

```bash
# Boot with QEMU
qemu-system-aarch64 \
  -kernel vmlinuz-doki-os \
  -initrd doki-os-initramfs-aarch64.tar.gz \
  -append "console=ttyS0 init=/sbin/doki-init" \
  -m 512 -nographic
```

### qcow2 (persistent disk)

Ext4 disk with persistent storage. Packages survive reboots.

```bash
# Boot with QEMU
qemu-system-aarch64 \
  -kernel vmlinuz-doki-os \
  -initrd doki-os-initramfs-aarch64.tar.gz \
  -append "console=ttyS0 init=/sbin/doki-init root=/dev/vda" \
  -drive file=doki-os-vm-aarch64.qcow2,format=qcow2 \
  -m 1024 -nographic
```

### OCI image

Run doki-OS as a container (for testing/CI):

```bash
docker pull doki/doki-os:latest
docker run --privileged doki/doki-os:latest
```

## What's Inside

```
doki-OS
├── Kernel 7.0+ (doki-os flavor)
│   ├── Container features: namespaces, cgroups v2, overlayfs, seccomp, Landlock
│   ├── Networking: veth, bridge, nftables, IPVS
│   ├── Virtio: blk, net, console, fs, balloon
│   ├── 9P: host↔guest file sharing
│   └── WiFi: iwlwifi, ath10k, ath11k, mt76, rtw88, brcmfmac (modules)
│
├── doki-init (PID 1)
│   ├── Mount /proc, /sys, /dev, /run, /tmp, /var
│   ├── Start dokid daemon
│   ├── Zombie reaping (PR_SET_CHILD_SUBREAPER)
│   ├── Signal forwarding (SIGTERM → graceful shutdown)
│   └── WiFi setup (wpa_supplicant + udhcpc)
│
├── Doki Container Engine
│   ├── doki (CLI, 108+ commands)
│   ├── dokid (daemon, Docker API v1.54 + libpod v5 + CRI)
│   ├── doki-compose (Compose 2026)
│   ├── doki-kube (Kubernetes components)
│   └── doki-kubectl (kubectl compatible)
│
├── Alpine Base
│   ├── musl libc
│   ├── BusyBox (core utilities)
│   ├── apk-tools (package manager)
│   └── OpenRC (service management)
│
└── Networking Tools
    ├── iproute2 (ip, bridge, tc)
    ├── nftables (firewall/NAT)
    ├── wireless-tools + wpa_supplicant (WiFi)
    └── udhcpc (DHCP client)
```

## Kernel Configuration

The doki-os kernel is based on Alpine's `virt` config with these additions:

- **WiFi drivers** as modules (for downloading packages without ethernet)
- **Landlock ABI v9** (unprivileged sandboxing)
- **fs-verity** (overlay integrity verification)
- **io_uring** (async I/O)
- Stripped: GPU/DRM, sound, input devices, most physical hardware drivers

## Repository

doki-OS packages are in the `doki/` repository:

```
doki/
├── doki/              # CLI binary
├── dokid/             # Daemon + OpenRC init script
├── doki-compose/      # Compose engine
├── doki-init/         # PID 1 for VM
├── doki-kube/         # Kubernetes components
├── doki-kubectl/      # kubectl compatible
├── doki-os-base/      # Metapackage (depends on all Doki packages)
├── doki-os-kernel/    # Custom kernel 7.0+
└── doki-os-vm/        # Metapackage for VM images
```

## Building

### Prerequisites

```bash
# On Alpine Linux
apk add abuild apk-tools alpine-conf busybox fakeroot syslinux xorriso \
    grub mtools sfdisk dosfstools squashfs-tools go
```

### Build packages

```bash
# Build all doki packages
for pkg in doki dokid doki-compose doki-init doki-kube doki-kubectl doki-os-base doki-os-kernel; do
    (cd doki/$pkg && abuild -r)
done
```

### Build images

```bash
# initramfs (all in RAM)
./scripts/mkimage.sh \
    --arch aarch64 \
    --profile doki_os_initramfs \
    --repository ./packages/aarch64 \
    --repository https://dl-cdn.alpinelinux.org/alpine/edge/main \
    --repository https://dl-cdn.alpinelinux.org/alpine/edge/community \
    --outdir output/ \
    --tag 0.9.5

# qcow2 (persistent disk)
./scripts/mkimage.sh \
    --arch aarch64 \
    --profile doki_os_vm \
    --repository ./packages/aarch64 \
    --repository https://dl-cdn.alpinelinux.org/alpine/edge/main \
    --repository https://dl-cdn.alpinelinux.org/alpine/edge/community \
    --outdir output/ \
    --tag 0.9.5
```

## Download

Pre-built images are available at:

```
https://github.com/OpceanAI/DokiOS/releases/latest/
├── doki-os-vm-aarch64.img.gz
├── doki-os-vm-x86_64.img.gz
├── doki-os-initramfs-aarch64.tar.gz
├── doki-os-initramfs-x86_64.tar.gz
├── vmlinuz-doki-os-aarch64
├── vmlinuz-doki-os-x86_64
└── keys/
    └── doki-os.pub
```

## Usage with Doki

When Doki runs on macOS or Android, it automatically downloads and boots doki-OS:

```bash
# macOS: automatic VM management
dokid &
# [INFO] Downloading doki-os-vm-aarch64.qcow2...
# [INFO] Verifying signature... ✓
# [INFO] Starting VM...
# [INFO] doki-OS ready in 2.8s

doki run nginx
# Container runs inside the doki-OS VM
```

## Differences from Alpine

| Aspect | Alpine 3.24 | doki-OS |
|---|---|---|
| Kernel | 6.18 LTS (generic) | 7.0+ (container-optimized) |
| Init | BusyBox init + OpenRC | doki-init (Go, PID 1) |
| Container engine | Not included | Doki pre-installed |
| WiFi | Included | Included + auto-configured |
| Boot time | 10-30s | <3s |
| Size (VM) | ~80MB | ~18MB |
| Purpose | General-purpose server/desktop | Container engine VM |

## License

- Alpine Linux components: MIT, GPL-2.0 (kernel), various
- Doki components: GPL-3.0 (due to BusyBox integration)
- doki-OS branding and integration: GPL-3.0
