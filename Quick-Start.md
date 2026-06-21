# Quick Start

This tutorial takes ~5 minutes and walks you through: download → run in QEMU → login → install extra packages → setup SSH → setup cloudflared.

## 0. Prerequisites

- DokiOS image downloaded from [Releases](https://github.com/OpceanAI/DokiOS/releases)
- ~2 GB free RAM for QEMU
- ~5 GB free disk for the image + storage

## 1. Download the Image

Get the image for your architecture:

| File | Architecture |
|:-----|:-------------|
| `dokios-0.10.0-x86_64.img` | x86_64 |
| `dokios-0.10.0-aarch64.img` | aarch64 |
| `dokios-0.10.0-armv7.img` | armv7 |

```bash
# Example: aarch64
wget https://github.com/OpceanAI/DokiOS/releases/download/v0.10.0/dokios-0.10.0-aarch64.img
ls -lh dokios-0.10.0-aarch64.img
# 600M
```

## 2. Run in QEMU

**x86_64:**
```bash
qemu-system-x86_64 -m 2048 \
    -drive format=raw,file=dokios-0.10.0-x86_64.img \
    -display none -serial mon:stdio
```

**aarch64:**
```bash
qemu-system-aarch64 -M virt -m 1024 -cpu cortex-a57 \
    -drive format=raw,file=dokios-0.10.0-aarch64.img \
    -nographic -serial mon:stdio
```

**armv7:**
```bash
qemu-system-arm -M virt -m 1024 \
    -drive format=raw,file=dokios-0.10.0-armv7.img \
    -nographic -serial mon:stdio
```

## 3. Login

```
Welcome to (none) DokiOS 0.10.0 (Linux 7.1.0 aarch64)

Arch:   aarch64

(none) login: root
Password: [press Enter]
```

You'll see the skull ASCII art and fastfetch banner, ending with a `doki-os:~$` prompt.

## 4. Verify the System

```bash
# DokiOS identification
cat /etc/os-release
# NAME="DokiOS"
# VERSION=0.10.0
# ID=dokios
# PRETTY_NAME="DokiOS 0.10.0 (Linux 7.1.0)"

# Doki engine version
doki version
# Client: Doki
#  Version:    0.10.0
#  API version: 1.54
#  Go version:  go1.26.4
#  OS/Arch:     linux/arm64

# Kernel
uname -a
# Linux doki-os 7.1.0-0-doki-os-doki-os #1 SMP ... aarch64 Linux

# Disk usage
df -h
# Filesystem      Size  Used Avail Use% Mounted on
# /dev/root        365M  196M  148M  57% /

# Memory
free -h
#               total        used        free      shared  buff/cache   available
# Mem:           963M        138M        720M         12M        104M        786M
```

## 5. Install Extra Packages

DokiOS uses Alpine's `apk` package manager. First, configure network:

```bash
# Check network (DHCP should be automatic)
ip addr show eth0
# Test connectivity
ping -c 3 dl-cdn.alpinelinux.org

# Update package index
apk update

# Install packages
apk add htop tmux caddy

# List installed packages
apk info | wc -l
```

## 6. Setup SSH Access

DokiOS has openssh server pre-installed, but you need to add your public key:

```bash
# On your host machine
ssh-keygen -t ed25519 -C "dokios-access"

# Copy the public key to DokiOS
# (replace the IP with the one from `ip addr show eth0`)
ssh-copy-id root@192.168.1.100
# or manually:
mkdir -p /root/.ssh
echo "ssh-ed25519 AAAA... your-key" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```

Then from your host:

```bash
ssh root@192.168.1.100
```

## 7. Setup Cloudflare Tunnel (Optional)

The `doki-tunnel` helper makes exposing DokiOS to the internet trivial:

```bash
# Get a tunnel token from https://one.dash.cloudflare.com/
# (create a tunnel, copy the TUNNEL_TOKEN)

# Method 1: Direct
doki-tunnel eyJhIjoiNjE...

# Method 2: Persistent (auto-starts on next login)
echo 'TUNNEL_TOKEN=eyJhIjoiNjE...' > /etc/doki-tunnel.conf
chmod 600 /etc/doki-tunnel.conf
# Logout and back in, cloudflared auto-starts
```

## 8. Run a Container with Doki

```bash
# Pull an image (uses Doki's Docker-API-compatible daemon)
dokid > /var/log/dokid.log 2>&1 &
sleep 2

# Try Docker CLI (Doki is API-compatible)
export DOCKER_HOST=unix:///var/run/doki.sock
# Note: DokiOS doesn't have a default socket path configured; use the doki CLI directly

# Native doki CLI
doki pull alpine
doki images
doki run --rm alpine echo "Hello from Doki"
```

## 9. Cleanup

To power off cleanly:

```bash
poweroff
# or
shutdown -h now
```

In QEMU, this exits cleanly and the image file is safe to delete.

## Next Steps

- [Installation](Installation) — Flash to SD card, customize, install
- [Configuration](Configuration) — All DokiOS settings
- [Architecture](Architecture) — How DokiOS works internally
- [Troubleshooting](Troubleshooting) — If something doesn't work
