# Storage

DokiOS uses a simple two-partition storage layout with squashfs modloop for the base OS and ext4 for persistent changes. This is the Alpine standard, adapted for DokiOS.

## Storage Layout

```
┌─────────────────────────────────────────┐
│  MBR (512 bytes)                         │
├─────────────────────────────────────────┤
│  Partition 1: FAT32 boot (200MB)         │
│  ─────────────────────────────────────   │
│  /vmlinuz              (kernel)          │
│  /initramfs            (mkinitfs)         │
│  /modloop              (squashfs rootfs)  │
│  /grub/                (x86_64 only)      │
├─────────────────────────────────────────┤
│  Partition 2: ext4 root (400MB)          │
│  ─────────────────────────────────────   │
│  /bin, /sbin, /usr, /etc, /var, /home,   │
│  /root, /opt, /lib, ...                 │
│  (Alpine + Doki binaries)                │
└─────────────────────────────────────────┘
```

## Partitions

### Partition 1: Boot (FAT32, 200MB)

| File | Purpose | Size |
|:-----|:--------|-----:|
| `vmlinuz` (x86_64) / `Image` (aarch64) / `zImage` (armv7) | Compressed kernel | 7-50 MB |
| `initramfs` | mkinitfs initramfs with all kernel modules | 6-37 MB |
| `modloop` | Squashfs of the read-only root filesystem | 33-75 MB |
| `grub/` (x86_64 only) | GRUB 2.06 bootloader | 5 MB |

The FAT32 filesystem is read-only by default but can be remounted `rw` for updates.

### Partition 2: Root (ext4, 400MB)

The root filesystem is `ext4` mounted read-write. It contains:

- All Alpine packages extracted from the modloop
- Doki binaries in `/usr/bin/`
- Configuration files in `/etc/`
- Persistent data in `/var/` (apk cache, sshd state)
- User home directories (`/root/`, `/home/`)
- Optional mounts in `/mnt/`, `/media/`, `/opt/`

**The root partition is only 400MB** in the default image. To add more storage:

1. Resize the partition with `parted` or `fdisk`
2. Resize the filesystem with `resize2fs`
3. Or attach additional storage via `/etc/fstab`

```sh
# Example: resize partition 2 to fill disk
parted /dev/sda resizepart 2 100%
resize2fs /dev/sda2
```

## modloop (Squashfs)

The **modloop** is a Squashfs-compressed read-only filesystem containing the Alpine + Doki base:

- Contains 109 packages (Alpine edge + Doki binaries)
- Mounted by mkinitfs during boot
- Files are extracted to a tmpfs (or the root partition in disk-based images)
- After extraction, the modloop is no longer needed (can be unmounted)

### How modloop works

```
Boot:
  1. mkinitfs finds modloop on boot media
  2. Mounts modloop → /media/x/ (read-only)
  3. Applies apkovl overlay (if present)
  4. Installs packages listed in /etc/apk/world from modloop
  5. switch_root to /sbin/init
```

### Modloop Contents

```
/media/x/
├── bin/                 (busybox, doki, dokid, etc.)
├── sbin/
├── usr/
├── etc/
├── lib/
├── lib/modules/         (kernel modules)
└── var/cache/apk/       (package cache)
```

### Replacing the modloop

To update the modloop (e.g., add packages):

```sh
# Inside the build environment
mksquashfs /tmp/updated-rootfs /out/rootfs-x86_64.squashfs \
    -comp xz -b 1M -Xbcj x86 -noappend

# Replace the modloop in the boot partition
mount /dev/sda1 /mnt/boot
cp /out/rootfs-x86_64.squashfs /mnt/boot/modloop
umount /mnt/boot

# Or for QEMU, replace in the image file
# (see Building wiki for full process)
```

## Persistent vs Ephemeral

### Persistent (survives reboot)

| Path | Why persistent |
|:-----|:--------------|
| `/etc/*` | Configuration (manual changes, firstboot.sh writes) |
| `/root/.ssh/authorized_keys` | SSH key (added manually) |
| `/etc/dokios-firstboot-done` | First-boot marker |
| `/var/cache/apk/` | Package cache (faster `apk add`) |
| `/var/empty/` | sshd privilege separation dir |
| `/etc/ssh/ssh_host_*_key` | SSH host keys (generated on first boot) |
| `/home/*` | User home directories |
| `/opt/*` | Optional software |

### Ephemeral (cleared on reboot)

| Path | Why ephemeral |
|:-----|:--------------|
| `/var/log/*` | Logs (no log rotation by default) |
| `/tmp/*` | tmpfs (cleared on reboot) |
| `/run/*` | tmpfs (cleared on reboot) |
| `/var/run/*` | Alias for `/run` (same) |

`/var/log` is on the root partition, so it persists across reboots. To make it ephemeral:

```sh
# Add to /etc/fstab
tmpfs /var/log tmpfs defaults,size=32M 0 0
```

## Adding Storage

### USB drive or SD card (Raspberry Pi)

```sh
# Find the device
lsblk

# Create ext4 filesystem
mkfs.ext4 -L DOKI_DATA /dev/sda1

# Mount point
mkdir -p /mnt/data

# Add to /etc/fstab
UUID=<uuid> /mnt/data ext4 defaults,noatime 0 2

# Mount
mount /mnt/data
```

### NFS mount

```sh
# Install NFS client
apk add nfs-utils

# Add to /etc/fstab
nas.example.com:/export/dokios /mnt/nfs nfs defaults,_netdev 0 0
```

### iSCSI

```sh
# Install open-iscsi
apk add open-iscsi

# Discover targets
iscsiadm -m discovery -t sendtargets -p <portal>

# Login
iscsiadm -m node -T <target> -p <portal> --login

# Partition, format, mount as usual
```

## Resizing the Image

The default 600MB image is small. To create a larger image:

```sh
# Create a new image with more space
dd if=/dev/zero of=dokios-0.10.0-x86_64-large.img bs=1M count=2048

# Replicate partition table
sfdisk -d dokios-0.10.0-x86_64.img | sfdisk dokios-0.10.0-x86_64-large.img

# Resize partition 2
parted dokios-0.10.0-x86_64-large.img resizepart 2 100%
# Or
sfdisk --part-attrs dokios-0.10.0-x86_64-large.img

# Resize filesystem
# First mount the partition, then resize2fs
LOOP=$(losetup --partscan --find --show dokios-0.10.0-x86_64-large.img)
e2fsck -f ${LOOP}p2
resize2fs ${LOOP}p2
losetup -d $LOOP
```

## Backup and Restore

### Backup the entire image

```sh
# To a file
dd if=/dev/sdX of=dokios-backup.img bs=4M status=progress

# To a compressed file
dd if=/dev/sdX bs=4M status=progress | gzip > dokios-backup.img.gz
```

### Restore

```sh
gunzip -c dokios-backup.img.gz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

### Backup specific files

```sh
# Mount and tar
mkdir -p /mnt/backup
mount /dev/sdX2 /mnt/backup
tar czf dokios-config-backup.tar.gz -C /mnt/backup etc/
umount /mnt/backup
```

## Disk Performance

DokiOS uses ext4 with `rw,relatime` mount options. For better performance:

### SSD optimization

```sh
# Add to /etc/fstab
UUID=<uuid> / ext4 rw,relatime,noatime,discard 0 1
```

- `noatime`: Don't update access time (less I/O)
- `discard`: Enable TRIM for SSDs (only on SSDs, not SD cards)

### SD card (Raspberry Pi)

```sh
# /etc/fstab
UUID=<uuid> / ext4 rw,relatime,noatime 0 1
# NO discard — TRIM can wear out SD cards faster
```

## Storage Statistics

| | x86_64 | aarch64 | armv7 |
|:--|------:|-------:|-----:|
| Image size | 600 MB | 600 MB | 600 MB |
| Boot partition | 200 MB | 200 MB | 200 MB |
| Boot used | ~100 MB | ~120 MB | ~70 MB |
| Root partition | 400 MB | 400 MB | 400 MB |
| Root used (fresh) | ~200 MB | ~180 MB | ~170 MB |
| Root free (fresh) | ~200 MB | ~220 MB | ~230 MB |
| modloop (squashfs) | 75 MB | 34 MB | 33 MB |
| Initramfs | 6.6 MB | 37 MB | 30 MB |
| Kernel | 12 MB | 50 MB | 7.7 MB |
| Memory (idle) | 144 MB | 72 MB | 42 MB |

## Troubleshooting Storage

### "No space left on device" during `apk add`

The root partition is 400MB. If you fill it up:

1. Check disk usage: `df -h`
2. Clean apk cache: `apk cache clean`
3. Remove unused packages: `apk del <pkg>`
4. Resize the image (see above)

### Modloop not found

If mkinitfs can't find the modloop:

1. Check boot partition is mounted: `ls /media/*/modloop`
2. Check kernel modules for your storage are loaded: `lsmod`
3. Check that `modules=loop,squashfs,...` is in kernel cmdline
4. Check the modloop filename: must be `/modloop` in boot partition

### Filesystem corruption

If ext4 is corrupted (rare with journaling):

```sh
# Boot from rescue media (Alpine ISO, etc.)
# Or add init=/bin/sh to kernel cmdline
e2fsck /dev/sda2
# Or if read-only:
e2fsck -f /dev/sda2
```

DokiOS doesn't auto-fsck on boot, so add to inittab if needed:

```sh
::sysinit:/bin/busybox e2fsck -p /dev/sda2
```
