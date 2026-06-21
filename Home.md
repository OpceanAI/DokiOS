# DokiOS Wiki

Welcome to the DokiOS documentation. DokiOS is an Alpine-based Linux distribution designed to run the [Doki](https://github.com/OpceanAI/Doki) container engine out of the box.

## Pages

### Getting Started

- [Quick Start](Quick-Start) — Boot DokiOS in 5 minutes
- [Installation](Installation) — Detailed install on QEMU, Raspberry Pi, or bare metal
- [Platform Compatibility](Platform-Compatibility) — Tested architectures and machines

### Configuration

- [Configuration](Configuration) — DokiOS settings, inittab, fstab
- [Networking](Networking) — DHCP, static IP, cloudflared
- [Storage](Storage) — rootfs, modloop, persistence
- [Security](Security) — SSH, firewall, hardening

### Advanced

- [Architecture](Architecture) — Boot flow, kernel, init system
- [Building](Building) — Build DokiOS from source
- [Troubleshooting](Troubleshooting) — Common issues and fixes

## About DokiOS

DokiOS is a minimal, custom-branded Alpine Linux distribution that ships with Doki v0.10.0 pre-installed. It provides a fast-booting, low-overhead environment with all the tools needed to deploy and manage containers.

| | |
|:--|:--|
| **Image size** | 600 MB |
| **Boot time** | <3 seconds (QEMU) |
| **Memory (idle)** | 70-150 MB |
| **Kernel** | Linux 7.1.0 (mainline) |
| **Init** | busybox-init |
| **Architectures** | x86_64, aarch64, armv7 |

## Quick Links

- [GitHub Repository](https://github.com/OpceanAI/DokiOS)
- [Releases](https://github.com/OpceanAI/DokiOS/releases)
- [Doki Container Engine](https://github.com/OpceanAI/Doki)
- [Issue Tracker](https://github.com/OpceanAI/DokiOS/issues)
