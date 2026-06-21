# Installation

DokiOS ships as 3 disk images (one per architecture) plus pre-installed Doki v0.10.0 binaries. Pick the image for your platform.

## Image Variants

| File | Architecture | Use case |
|:-----|:-------------|:---------|
| `dokios-0.10.0-x86_64.img` | x86_64 | QEMU, VirtualBox, VMware, cloud VMs, bare metal |
| `dokios-0.10.0-aarch64.img` | aarch64 | QEMU, Graviton, Apple Silicon (via QEMU), Raspberry Pi 4/5 64-bit |
| `dokios-0.10.0-armv7.img` | armv7 | QEMU, Raspberry Pi 2/3, BeagleBone, other 32-bit ARM boards |

All three images have a unified layout:

```
dokios-0.10.0-{arch}.img (600MB)
├── Partition 1: FAT32 boot (200MB)
│   ├── vmlinuz / Image / zImage    (kernel)
│   ├── initramfs                   (mkinitfs initramfs)
│   ├── modloop                     (squashfs of rootfs)
│   └── grub/                       (x86_64 only)
└── Partition 2: ext4 root (400MB, read-write)
    └── (Alpine + Doki binaries + customizations)
```

## QEMU Installation

### x86_64

```bash
qemu-system-x86_64 -m 2048 \
    -drive format=raw,file=dokios-0.10.0-x86_64.img \
    -display none -serial mon:stdio
```

The serial console is `ttyS0` (115200 baud). To enable graphics:

```bash
qemu-system-x86_64 -m 2048 \
    -drive format=raw,file=dokios-0.10.0-x86_64.img \
    -display gtk -serial stdio
```

### aarch64

```bash
qemu-system-aarch64 -M virt -m 1024 -cpu cortex-a57 \
    -drive format=raw,file=dokios-0.10.0-aarch64.img \
    -nographic -serial mon:stdio
```

For Apple Silicon Macs (using native QEMU via Homebrew):

```bash
brew install qemu
qemu-system-aarch64 -M virt -m 1024 -cpu cortex-a57 \
    -drive format=raw,file=dokios-0.10.0-aarch64.img \
    -nographic
```

### armv7 (Raspberry Pi)

QEMU emulation:

```bash
qemu-system-arm -M raspi3b -m 1024 \
    -drive format=raw,file=dokios-0.10.0-armv7.img \
    -nographic
```

For real Raspberry Pi hardware, flash the `armv7` image to SD card (see below).

## Raspberry Pi Installation

### Finding your SD Card

```bash
# Linux
lsblk
# Look for /dev/sdX or /dev/mmcblkX

# macOS
diskutil list
# Look for /dev/diskN (external, physical)

# Windows
# Use Disk Management or wmic logicaldisk
```

### Flashing

**Linux:**
```bash
sudo dd if=dokios-0.10.0-armv7.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

**macOS:**
```bash
sudo dd if=dokios-0.10.0-armv7.img of=/dev/rdiskN bs=4m status=progress
sync
```

**Windows (use balenaEtcher or Rufus):**

1. Download [balenaEtcher](https://etcher.balena.io/)
2. Select the `.img` file
3. Select your SD card
4. Click Flash

### First Boot on Raspberry Pi

1. Insert SD card into Pi
2. Connect serial console via GPIO (Pi 3: pin 6 GND, pin 8 TX, pin 10 RX → USB-TTL adapter)
3. Power on
4. Login as `root` (no password)
5. Configure WiFi: `setup-interfaces -r` (Alpine helper)

## VirtualBox Installation

The x86_64 image works in VirtualBox but needs conversion to VDI:

```bash
# Install qemu-utils for qemu-img
sudo apt install qemu-utils

# Convert to VDI
qemu-img convert -O vdi dokios-0.10.0-x86_64.img dokios-0.10.0-x86_64.vdi
```

Then in VirtualBox:
1. New VM → Type: Linux, Version: Other Linux 64-bit
2. Memory: 2048 MB minimum
3. Hard disk: Use existing VDI
4. Settings → System → Enable EFI (optional, DokiOS boots both ways)
5. Settings → Network → Adapter 1 → Bridged Adapter (for SSH access)
6. Start VM

## VMware Installation

```bash
qemu-img convert -O vmdk dokios-0.10.0-x86_64.img dokios-0.10.0-x86_64.vmdk
```

Then in VMware:
1. Create new VM → Custom
2. Hardware compatibility: Workstation 17.x
3. Guest OS: Linux, Other Linux 5.x kernel 64-bit
4. Memory: 2048 MB
5. Network: NAT or Bridged
6. Use existing VMDK
7. Power on

## Cloud Installation

### AWS Graviton (aarch64)

```bash
# Convert to raw AMI format
qemu-img convert -O raw dokios-0.10.0-aarch64.img dokios-0.10.0-aarch64.raw

# Upload to S3
aws s3 cp dokios-0.10.0-aarch64.raw s3://my-bucket/

# Import as snapshot
aws ec2 import-snapshot \
    --description "DokiOS 0.10.0 aarch64" \
    --disk-container "file://dokios-0.10.0-aarch64.raw" \
    --region us-east-1

# Register AMI from snapshot
# (use the AWS Console or aws ec2 register-image)
```

**Recommended instance type:** `t4g.small` (2 vCPU, 2 GB RAM, $0.0168/hour)

### Google Cloud (x86_64)

```bash
# Convert and compress
qemu-img convert -O raw dokios-0.10.0-x86_64.img dokios-0.10.0-x86_64.raw
tar -czf dokios-0.10.0-x86_64.tar.gz dokios-0.10.0-x86_64.raw

# Upload to GCS
gsutil cp dokios-0.10.0-x86_64.tar.gz gs://my-bucket/

# Create image
gcloud compute images create dokios-0-10-0 \
    --source-uri gs://my-bucket/dokios-0.10.0-x86_64.tar.gz \
    --guest-os-features VIRTIO_SCSI_MULTIQUEUE
```

## Verification

After installation, verify DokiOS is working:

```bash
# Check DokiOS identity
cat /etc/os-release | head -3
# NAME="DokiOS"
# VERSION=0.10.0
# ID=dokios

# Check Doki is installed
doki version | head -5
# Client: Doki
#  Version:    0.10.0
#  API version: 1.54
#  Go version:  go1.26.4
#  OS/Arch:     linux/{arch}

# Check custom branding
cat /etc/motd | head -5
# (should show skull ASCII art)

# Check kernel
uname -a
```

## Troubleshooting

If the image doesn't boot, see [Troubleshooting](Troubleshooting) for:
- "No bootable device" errors
- Black screen after GRUB
- Kernel panic
- Network not working
- Login issues
