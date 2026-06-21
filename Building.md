# Building DokiOS from Source

This guide walks through building DokiOS images from source. The process takes 30-60 minutes and requires Docker.

## Prerequisites

- **Docker** 20.10+ with buildx
- **5 GB free disk space**
- **4 GB RAM** (for cross-compilation)
- **Internet access** for downloading source code, packages, and Doki binaries

Verify:

```sh
docker --version
docker info | grep "Server Version"
```

## Overview

The build is done in Docker containers for cross-platform support:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  x86_64 (native)│    │  aarch64 (qemu)  │    │  armv7 (qemu)   │
│  Container      │    │  Container       │    │  Container      │
└────────┬────────┘    └────────┬────────┘    └────────┬────────┘
         │                       │                       │
         │   mksquashfs          │   mksquashfs          │   mksquashfs
         │   mkinitfs            │   mkinitfs            │   mkinitfs
         │                       │                       │
         ▼                       ▼                       ▼
   rootfs-x86_64.squashfs   rootfs-aarch64.squashfs  rootfs-armv7.squashfs
   initramfs-x86_64         initramfs-aarch64        initramfs-armv7
         │                       │                       │
         └───────────┬───────────┴───────────┬───────────┘
                     │                       │
                     ▼                       ▼
            x86_64/bzImage            aarch64/Image    armv7/zImage
                     │                       │                       │
                     └───────────┬───────────┴───────────┬───────────┘
                                 │                       │
                                 ▼                       ▼
                       dokios-0.10.0-x86_64.img    dokios-0.10.0-aarch64.img    dokios-0.10.0-armv7.img
```

## Step 1: Set Up Build Directories

```sh
# Create work directory
mkdir -p /root/dokios-build
cd /root/dokios-build

# Workspace structure
mkdir -p output          # Final images
mkdir -p work            # Intermediate files
```

## Step 2: Build Kernel (Optional)

The default DokiOS uses pre-built kernels. To build a custom kernel:

```sh
# Clone the kernel source
cd /root/dokios-build
git clone --depth=1 --branch=v7.1 \
    https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git \
    linux-7.1

cd linux-7.1

# Use DokiOS kernel config
# (these are stored in the build output of an existing DokiOS image)
cp /root/dokios-out/x86_64/bzImage .config  # as example

# Or use Alpine's config
wget https://git.alpinelinux.org/aports/plain/main/linux-lts/config-x86_64.alpine
mv config-x86_64.alpine .config

# Build
make -j$(nproc) ARCH=x86_64 bzImage modules dtbs

# Install modules
make modules_install INSTALL_MOD_PATH=/root/dokios-build/work/modules-x86_64
```

For ARM:

```sh
# Debian/Ubuntu
apt-get install gcc-aarch64-linux-gnu gcc-arm-linux-gnueabihf

# Build
make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image modules dtbs
make modules_install ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    INSTALL_MOD_PATH=/root/dokios-build/work/modules-aarch64

# ARMv7
make -j$(nproc) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage modules dtbs
make modules_install ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
    INSTALL_MOD_PATH=/root/dokios-build/work/modules-armv7
```

## Step 3: Create Build Containers

### x86_64 (native)

```sh
docker run -d --name dokios-build-x86_64 \
    -v /root/dokios-build:/out \
    --privileged \
    alpine:edge \
    sh -c "apk add --no-cache apk-tools mkinitfs squashfs-tools grub grub-bios xorriso mtools sfdisk dosfstools syslinux && while true; do sleep 3600; done"
```

### aarch64 (using qemu-user-static)

```sh
docker run -d --name dokios-build-aarch64 \
    --platform linux/arm64 \
    -v /root/dokios-build:/out \
    --privileged \
    alpine:edge \
    sh -c "apk add --no-cache apk-tools mkinitfs squashfs-tools && while true; do sleep 3600; done"
```

### armv7 (using qemu-user-static)

```sh
docker run -d --name dokios-build-armv7 \
    --platform linux/arm/v7 \
    -v /root/dokios-build:/out \
    --privileged \
    alpine:edge \
    sh -c "apk add --no-cache apk-tools mkinitfs squashfs-tools && while true; do sleep 3600; done"
```

Verify:

```sh
docker ps
# Should show all 3 build containers running
```

## Step 4: Build Root Filesystem

### Create Base Rootfs (Alpine + packages)

Run in each container:

```sh
docker exec dokios-build-x86_64 sh << 'EOF'
# Create base rootfs
rm -rf /tmp/rootfs
mkdir -p /tmp/rootfs

# Initialize apk
mkdir -p /tmp/rootfs/etc/apk /var/cache/apk /tmp/rootfs/lib/apk
cp -r /etc/apk/keys /etc/apk/repositories /tmp/rootfs/etc/apk/

# Install base packages
apk add --no-cache --root=/tmp/rootfs --keys-dir=/etc/apk/keys --initdb \
    alpine-baselayout busybox musl openrc

# Install DokiOS packages
apk add --no-cache --root=/tmp/rootfs --keys-dir=/etc/apk/keys \
    bash zsh openssh openssh-client git curl wget bind-tools \
    ca-certificates neovim fastfetch

echo "Base rootfs built successfully"
ls /tmp/rootfs/bin/busybox /tmp/rootfs/usr/bin/fastfetch
EOF
```

Repeat for aarch64 and armv7 (in their respective containers).

### Apply DokiOS Customizations

The customization script is at `/tmp/customize-rootfs.sh` (in the build container). Create it:

```sh
docker cp /path/to/customize-rootfs.sh dokios-build-x86_64:/tmp/

docker exec dokios-build-x86_64 sh -c '
chmod +x /tmp/customize-rootfs.sh
/tmp/customize-rootfs.sh /tmp/rootfs x86_64 ttyS0

# Fix /etc/passwd
sed -i "1s|^.*\$|root:x:0:0:root:/root:/bin/bash|" /tmp/rootfs/etc/passwd

# Verify
head -1 /tmp/rootfs/etc/passwd
ls /tmp/rootfs/etc/fastfetch/
'
```

The `customize-rootfs.sh` script (see `scripts/customize-rootfs.sh` in the repo):

- Sets `/etc/os-release` to DokiOS branding
- Creates `/etc/motd` with skull ASCII
- Creates `/etc/issue` with welcome banner
- Sets up `/etc/fastfetch/config.jsonc` and `logo.txt`
- Configures `/etc/profile.d/00-dokios.sh` for fastfetch
- Configures `/etc/profile.d/doki-tunnel.sh` for cloudflared
- Sets up `/etc/ssh/sshd_config`
- Creates `/etc/local.d/firstboot.sh` for SSH key generation
- Creates `/usr/local/bin/doki-tunnel` helper
- Sets bash as default shell for root
- Disables root password
- Sets hostname to `doki-os`

### Download Upstream Binaries

```sh
docker exec dokios-build-x86_64 sh << 'EOF'
mkdir -p /tmp/downloads
cd /tmp/downloads

# fastfetch 2.64.2 (Alpine package is musl-compatible)
# Already installed via apk add fastfetch above

# cloudflared upstream latest
wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64" \
    -O /tmp/rootfs/usr/bin/cloudflared
chmod +x /tmp/rootfs/usr/bin/cloudflared

# Verify
ls -lh /tmp/rootfs/usr/bin/cloudflared /tmp/rootfs/usr/bin/fastfetch
EOF
```

For ARM:

```sh
# aarch64
wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" \
    -O /tmp/rootfs/usr/bin/cloudflared
chmod +x /tmp/rootfs/usr/bin/cloudflared

# armv7
wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-armhf" \
    -O /tmp/rootfs/usr/bin/cloudflared
chmod +x /tmp/rootfs/usr/bin/cloudflared
```

### Add Doki v0.10.0 Binaries

```sh
# Copy Doki binaries from upstream release
DOKI_VERSION="0.10.0"

for arch in x86_64 aarch64 armv7; do
    ARCH_PATH=$arch
    if [ "$arch" = "x86_64" ]; then ARCH_PATH="amd64"; fi
    if [ "$arch" = "armv7" ]; then ARCH_PATH="armv7"; fi
    
    # Adjust based on actual upstream naming
    case $arch in
        x86_64)  URL_ARCH="linux-amd64" ;;
        aarch64) URL_ARCH="linux-arm64" ;;
        armv7)   URL_ARCH="linux-armv7" ;;
    esac
    
    for bin in doki dokid doki-compose doki-init doki-kube doki-kubectl; do
        wget -q "https://github.com/OpceanAI/Doki/releases/download/v${DOKI_VERSION}/${bin}-${URL_ARCH}" \
            -O "/tmp/rootfs/usr/bin/${bin}"
        chmod +x "/tmp/rootfs/usr/bin/${bin}"
    done
done

ls -lh /tmp/rootfs/usr/bin/doki*
```

## Step 5: Build modloop and initramfs

### modloop (Squashfs)

```sh
docker exec dokios-build-x86_64 sh << 'EOF'
mksquashfs /tmp/rootfs /out/rootfs-x86_64.squashfs \
    -comp xz -b 1M -Xbcj x86 -noappend
ls -lh /out/rootfs-x86_64.squashfs
EOF
```

For ARM (different `-Xbcj` value):

```sh
# aarch64
mksquashfs /tmp/rootfs /out/rootfs-aarch64.squashfs \
    -comp xz -b 1M -Xbcj arm -noappend

# armv7
mksquashfs /tmp/rootfs /out/rootfs-armv7.squashfs \
    -comp xz -b 1M -Xbcj arm -noappend
```

### initramfs

```sh
docker exec dokios-build-x86_64 sh << 'EOF'
# Get kernel version
KVER=$(ls /lib/modules/ | head -1)
echo "Kernel: $KVER"

# Generate initramfs
mkinitfs -F "base ata scsi usb cdrom virtio 9p squashfs ext4" \
    -o /out/initramfs-x86_64 "$KVER"

ls -lh /out/initramfs-x86_64
EOF
```

For ARM (modules need to be in the container's `/lib/modules/`):

```sh
# Inside aarch64 container
mkdir -p /lib/modules/7.1.0-0-doki-os-doki-os
cp -r /out/work/modules-aarch64/* /lib/modules/7.1.0-0-doki-os-doki-os/

mkinitfs -F "base ata scsi usb cdrom virtio 9p squashfs ext4" \
    -o /out/initramfs-aarch64 7.1.0-0-doki-os-doki-os
```

## Step 6: Assemble Disk Image

For each architecture, create a 600MB raw disk image with 2 partitions:

```sh
# Run in host (not in container)
cd /root/dokios-build

build_image() {
    local arch=$1
    local image="output/dokios-0.10.0-${arch}.img"
    
    # Create 600MB image
    dd if=/dev/zero of="$image" bs=1M count=600
    
    # Partition: 200MB boot + 400MB root
    LOOP=$(losetup --partscan --find --show "$image")
    sfdisk "$LOOP" <<EOF
label: dos
unit: sectors
start=2048, size=409600, type=6
start=411648, type=83
EOF
    losetup -d $LOOP
    
    # Format
    LOOP=$(losetup --partscan --find --show "$image")
    mkfs.vfat -F 32 ${LOOP}p1 -n DOKI_BOOT
    mkfs.ext4 -F -L DOKI_ROOT ${LOOP}p2
    losetup -d $LOOP
    
    # Mount
    LOOP=$(losetup --partscan --find --show "$image")
    mkdir -p /tmp/img-root /tmp/img-boot
    mount ${LOOP}p2 /tmp/img-root
    mount ${LOOP}p1 /tmp/img-boot
    
    # Extract modloop to root
    unsquashfs -d /tmp/img-root -f -no-progress /root/dokios-build/rootfs-${arch}.squashfs
    
    # Create device nodes
    mknod /tmp/img-root/dev/console c 5 1
    mknod /tmp/img-root/dev/null c 1 3
    if [ "$arch" = "x86_64" ]; then
        mknod /tmp/img-root/dev/ttyS0 c 4 64
    else
        mknod /tmp/img-root/dev/ttyAMA0 c 204 64
    fi
    chmod 666 /tmp/img-root/dev/*
    
    # Symlink init
    rm -f /tmp/img-root/sbin/init
    ln -sf /bin/busybox /tmp/img-root/sbin/init
    
    # fstab
    ROOT_UUID=$(blkid -o value -s UUID ${LOOP}p2)
    cat > /tmp/img-root/etc/fstab <<EOF
UUID=$ROOT_UUID / ext4 rw,relatime 0 1
tmpfs /var tmpfs defaults,size=64M 0 0
tmpfs /tmp tmpfs defaults,size=32M 0 0
EOF
    
    # Empty root password
    sed -i 's|^root:[^:]*:|root::|' /tmp/img-root/etc/shadow
    
    # Copy kernel and initramfs to boot
    case $arch in
        x86_64)  cp /root/dokios-out/x86_64/bzImage /tmp/img-boot/vmlinuz ;;
        aarch64) cp /root/dokios-out/aarch64/Image /tmp/img-boot/Image ;;
        armv7)   cp /root/dokios-out/armv7/zImage /tmp/img-boot/zImage ;;
    esac
    cp /root/dokios-build/initramfs-${arch} /tmp/img-boot/initramfs
    cp /root/dokios-build/rootfs-${arch}.squashfs /tmp/img-boot/modloop
    
    # GRUB (x86_64 only)
    if [ "$arch" = "x86_64" ]; then
        mkdir -p /tmp/img-boot/grub
        cat > /tmp/img-boot/grub/grub.cfg <<EOF
set timeout=5
set default=0
serial --unit=0 --speed=115200
terminal_input console serial
terminal_output console serial
menuentry "DokiOS 0.10.0 (kernel 7.1.0)" {
    linux /vmlinuz modules=loop,squashfs,sd-mod,usb-storage,virtio_blk \
          console=ttyS0,115200 net.ifnames=0 \
          root=UUID=$ROOT_UUID rootfstype=ext4 rootflags=rw,relatime
    initrd /initramfs
}
EOF
        grub-install --target=i386-pc --boot-directory=/tmp/img-boot --no-floppy $LOOP
    fi
    
    # Cleanup
    umount /tmp/img-root /tmp/img-boot
    losetup -d $LOOP
    rmdir /tmp/img-root /tmp/img-boot
    
    echo "Built: $image ($(du -h "$image" | cut -f1))"
}

build_image x86_64
build_image aarch64
build_image armv7
```

## Step 7: Verify the Image

Test each image with QEMU:

```sh
# x86_64
qemu-system-x86_64 -m 2048 \
    -drive format=raw,file=output/dokios-0.10.0-x86_64.img \
    -display none -serial mon:stdio

# aarch64
qemu-system-aarch64 -M virt -m 1024 -cpu cortex-a57 \
    -drive format=raw,file=output/dokios-0.10.0-aarch64.img \
    -nographic -serial mon:stdio

# armv7
qemu-system-arm -M virt -m 1024 \
    -drive format=raw,file=output/dokios-0.10.0-armv7.img \
    -nographic -serial mon:stdio
```

Check:

- Login prompt appears within 3 seconds
- Login as `root` (no password)
- Skull ASCII art in `/etc/motd`
- fastfetch shows DokiOS branding
- `doki version` returns v0.10.0
- `cloudflared --version` returns latest
- Reboot persists changes (test with `apk add htop`)

## Step 8: Create Release

```sh
cd /root/dokios-build

# Create a GitHub release
gh release create v0.10.0 \
    --title "DokiOS 0.10.0" \
    --notes "Initial release of DokiOS 0.10.0 with multi-arch support." \
    output/dokios-0.10.0-x86_64.img \
    output/dokios-0.10.0-aarch64.img \
    output/dokios-0.10.0-armv7.img
```

Or distribute via direct download, cloud storage, etc.

## Build Optimization

### Parallel Builds

```sh
# Run all 3 architectures in parallel
docker exec dokios-build-x86_64 bash -c "build_image x86_64" &
docker exec dokios-build-aarch64 bash -c "build_image aarch64" &
docker exec dokios-build-armv7 bash -c "build_image armv7" &
wait
```

### Use Build Cache

DokiOS uses Docker layer caching. Keep build containers running between builds:

```sh
# Don't run "docker rm" between builds
# Just re-run the build commands
```

### Reduce Image Size

```sh
# Strip debug symbols
strip /tmp/rootfs/usr/bin/doki*

# Compress modloop more aggressively
mksquashfs /tmp/rootfs /out/rootfs-x86_64.squashfs \
    -comp xz -b 1M -Xbcj x86 -noappend -Xcompression-level 9

# Use UPX for binaries (optional)
apk add upx
upx --best /tmp/rootfs/usr/bin/doki*
```

## Build Environment Cleanup

```sh
# Remove build containers
docker rm -f dokios-build-x86_64 dokios-build-aarch64 dokios-build-armv7

# Clean build artifacts
rm -rf /root/dokios-build/work

# Keep /root/dokios-build/output for testing
ls -lh /root/dokios-build/output/
```

## CI/CD Integration

Example GitHub Actions workflow (`.github/workflows/build.yml`):

```yaml
name: Build DokiOS

on:
  push:
    tags: ['v*']
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Build
        run: ./scripts/build.sh

      - name: Test
        run: ./scripts/test.sh

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: dokios-images
          path: output/*.img
```

## See Also

- [Architecture](Architecture) — How DokiOS is built
- [Storage](Storage) — Image layout
- [Configuration](Configuration) — Customizing DokiOS
- [Troubleshooting](Troubleshooting) — When builds fail
