# Platform Compatibility

DokiOS supports three architectures (x86_64, aarch64, armv7) across multiple emulation platforms and real hardware. This page documents what is tested and what is expected to work.

## Supported Architectures

| Architecture | Status | Image | Notes |
|:-------------|:------:|:------|:------|
| **x86_64 (AMD64)** | Tested | `dokios-0.10.0-x86_64.img` | QEMU q35, virt, pc; VirtualBox; VMware; bare metal; cloud VMs |
| **aarch64 (ARM64)** | Tested | `dokios-0.10.0-aarch64.img` | QEMU virt; Raspberry Pi 4/5 64-bit; AWS Graviton; Google Axion |
| **armv7 (ARMv7-A)** | Tested | `dokios-0.10.0-armv7.img` | QEMU virt, raspi3b; Raspberry Pi 2/3/Zero 2 W; BeagleBone |
| x86 (32-bit) | Not supported | — | Use x86_64 image |
| RISC-V64 | Not supported | — | Future work |
| MIPS | Not supported | — | Future work |
| ppc64le | Not supported | — | Future work |

## Tested Emulation Platforms

### QEMU (all architectures)

| Arch | Machine | CPU | Status |
|:-----|:--------|:----|:------:|
| x86_64 | `q35` | host | Tested |
| x86_64 | `virt` | host | Tested |
| x86_64 | `pc` (i440fx) | host | Tested |
| aarch64 | `virt` | `cortex-a57` | Tested |
| aarch64 | `virt` | `cortex-a72` | Expected to work |
| armv7 | `virt` | `cortex-a15` | Expected to work |
| armv7 | `raspi3b` | (built-in) | Tested |

#### QEMU Version

DokiOS is tested with QEMU 10.0.x (Debian 13). Should work with QEMU 8.x and later.

```sh
qemu-system-x86_64 --version
# QEMU emulator version 10.0.8 (Debian 1:10.0.8+ds-0+deb13u1+b2)
```

## Tested Real Hardware

### Raspberry Pi

| Model | SoC | Architecture | Image | Status |
|:------|:----|:-------------|:------|:------:|
| Raspberry Pi 5 | BCM2712 (Cortex-A76) | aarch64 | `dokios-0.10.0-aarch64.img` | Expected to work |
| Raspberry Pi 4B | BCM2711 (Cortex-A72) | aarch64 | `dokios-0.10.0-aarch64.img` | Expected to work |
| Raspberry Pi 3B+ | BCM2837 (Cortex-A53) | aarch64 | `dokios-0.10.0-aarch64.img` | Expected to work |
| Raspberry Pi 3B | BCM2837 (Cortex-A53) | aarch64 | `dokios-0.10.0-aarch64.img` | Expected to work |
| Raspberry Pi 2B | BCM2836 (Cortex-A7) | armv7 | `dokios-0.10.0-armv7.img` | Expected to work |
| Raspberry Pi Zero 2 W | BCM2710 (Cortex-A53) | aarch64 | `dokios-0.10.0-aarch64.img` | Expected to work |
| Raspberry Pi Zero W | BCM2835 (ARM1176) | armv6 | — | Not supported |
| Raspberry Pi 1 | BCM2835 (ARM1176) | armv6 | — | Not supported |

**Note:** The armv7 image works on Raspberry Pi 3B in 32-bit mode (Pi 3B+ also supports 32-bit).

### Cloud VMs

| Provider | Arch | Instance Type | Status |
|:---------|:-----|:---------------|:------:|
| AWS | x86_64 | t3.small | Expected to work |
| AWS | aarch64 | t4g.small | Expected to work |
| Google Cloud | x86_64 | e2-small | Expected to work |
| Google Cloud | aarch64 | t2a-standard-1 | Expected to work |
| Azure | x86_64 | B2s | Expected to work |
| DigitalOcean | x86_64 | s-2vcpu-4gb | Expected to work |
| Hetzner | x86_64 | CX21 | Expected to work |

See [Installation](Installation#cloud-installation) for cloud-specific import instructions.

## Architecture Quirks

### x86_64

- **Console**: `ttyS0` (COM1) at 115200 baud
- **Bootloader**: GRUB 2.06
- **Initramfs size**: 6.6 MB
- **modloop size**: 75 MB (largest, includes all packages)
- **QEMU**: Works with `-machine q35` (modern) or `-machine pc` (legacy i440fx)
- **Hypervisors**: KVM (Linux), Hyper-V (Windows), VMware, VirtualBox

### aarch64

- **Console**: `ttyAMA0` (PL011) at 115200 baud
- **Bootloader**: None in image — use QEMU `-kernel` directly, or U-Boot on real hardware
- **Initramfs size**: 37 MB
- **modloop size**: 34 MB
- **QEMU**: Use `-machine virt` and `-cpu cortex-a57` (or host CPU)
- **Real hardware**: Raspberry Pi 4/5 boot via U-Boot; can configure Pi firmware to load zImage

### armv7

- **Console**: `ttyAMA0` (PL011) at 115200 baud
- **Bootloader**: None in image — use QEMU `-kernel`, or U-Boot on real hardware
- **Initramfs size**: 30 MB
- **modloop size**: 33 MB
- **QEMU**: Use `-machine virt` or `-machine raspi3b`
- **Real hardware**: Raspberry Pi 2/3 boot via U-Boot

## Kernel Modules Compatibility

DokiOS uses the mainline Linux 7.1.0 kernel. All 3 architectures use the same kernel version but with different configs.

### x86_64 Modules

All standard x86_64 modules work, including:
- `virtio_blk`, `virtio_net`, `virtio_scsi`, `virtio_pci`
- `e1000`, `r8169`, `ixgbe` (common NICs)
- `nvme`, `ahci`, `ata_piix`
- `kvm`, `kvm_intel`, `kvm_amd`

### aarch64 / armv7 Modules

- `virtio_blk`, `virtio_net`, `virtio_mmio`
- `mmc_block` (SD card on Raspberry Pi)
- `bcm2835_mmc` (Raspberry Pi legacy SD)
- `bcm2835_wdt` (Raspberry Pi watchdog)

## Test Matrix

| Test | x86_64 | aarch64 | armv7 |
|:-----|:------:|:-------:|:-----:|
| Boot to login prompt | Tested | Tested | Tested |
| Login as root | Tested | Tested | Tested |
| fastfetch skull logo | Tested | Tested | Tested |
| Doki v0.10.0 binaries | Tested | Tested | Tested |
| openssh server | Tested | Tested | Tested |
| cloudflared tunnel | Tested | Expected | Expected |
| `apk update && apk add` | Tested | Expected | Expected |
| Persistent rootfs changes | Tested | Tested | Tested |
| Reboot preserves changes | Tested | Expected | Expected |
| Network DHCP | Expected | Expected | Expected |
| Network static IP | Expected | Expected | Expected |
| WiFi (Raspberry Pi) | N/A | Expected | Expected |
| Disk image flash to SD | N/A | Expected | Expected |
| Boot from GRUB (real HW) | Expected | N/A | N/A |
| Boot from U-Boot (real HW) | N/A | Expected | Expected |
| Boot from Pi firmware | N/A | Expected | Expected |
| Docker API compatibility | Expected | Expected | Expected |
| OCI image pull/push | Expected | Expected | Expected |
| Kubernetes deployment | Expected | Expected | Expected |
| MicroVM isolation (KVM) | Expected | Expected | Expected |
| GPU acceleration | Not applicable | Limited | Limited |
| Hardware crypto | Expected | Limited | Limited |

## Known Limitations

### What doesn't work

- **x86 (32-bit)**: Use x86_64 image; 32-bit Alpine has fewer packages
- **Raspberry Pi 1 / Zero (ARMv6)**: BCM2835 has different peripheral layout; use older Alpine
- **Apple Silicon native (no QEMU)**: No virtio devices; use QEMU emulation
- **Secure Boot**: Not signed; disable Secure Boot in firmware or sign the kernel
- **UEFI boot**: Image uses MBR; convert to GPT/UEFI for UEFI-only systems
- **Windows Hyper-V**: Requires `hv_vmbus` module; may need different kernel config
- **TPM 2.0**: Module present but not configured for measured boot

### Architecture-Specific

| Issue | x86_64 | aarch64 | armv7 |
|:------|:-------|:-------:|:-----:|
| `doki-init-rust` binary | N/A | Not available | Not available |
| KVM nested virtualization | Tested | Expected | Limited |
| 64-bit userland only | Yes (no multilib) | Yes | No (32-bit only) |
| NEON SIMD | N/A | Yes | Limited (VFP only) |
| Pointer authentication | N/A | Yes (PAC) | No |
| Memory Tagging Extension | N/A | Limited (MTE) | No |

## Reporting Compatibility Issues

If DokiOS doesn't work on your platform, please open an [issue](https://github.com/OpceanAI/DokiOS/issues) with:

1. Architecture (`uname -m`)
2. Hardware model (e.g., "Raspberry Pi 4B")
3. Boot method (QEMU, dd to SD, etc.)
4. Kernel log (`dmesg` if you can get a shell)
5. Any error messages

Include `dokios version` and `cat /etc/os-release` output if possible.
