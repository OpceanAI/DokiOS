# Troubleshooting

Common issues and fixes for DokiOS.

## Boot Issues

### "No bootable device" in QEMU

The image uses MBR. Check that the QEMU command points to the raw image file:

```sh
qemu-system-x86_64 \
    -drive format=raw,file=dokios-0.10.0-x86_64.img \
    -m 2048
```

If using copy-paste, ensure the path is correct and the file exists:

```sh
ls -lh dokios-0.10.0-x86_64.img
file dokios-0.10.0-x86_64.img
# Should show: DOS/MBR boot sector; partition 1: ...; partition 2: ...
```

### Black screen after GRUB (x86_64)

Usually a kernel panic. Press `e` in GRUB to edit the boot command. Add:

```
console=ttyS0,115200 earlyprintk
```

This shows kernel messages on the serial console.

### Kernel panic: "VFS: Unable to mount root fs"

The root partition UUID in the kernel cmdline doesn't match. To fix:

1. Mount the boot partition (in another Linux system or QEMU with rescue ISO):

   ```sh
   qemu-system-x86_64 \
       -drive format=raw,file=dokios-0.10.0-x86_64.img \
       -drive file=alpine-virt-3.24.iso,format=raw,if=virtio \
       -m 2048
   # In Alpine: mount /dev/vda1 /mnt; cat /mnt/grub/grub.cfg
   ```

2. Check the root=UUID matches the actual partition:

   ```sh
   blkid /dev/vda2
   # /dev/vda2: UUID="..."
   ```

3. Update `/mnt/grub/grub.cfg` with the correct UUID.

### "Failed to execute /init (error -8)"

`ENOEXEC`. The init script in the initramfs can't execute. Usually means wrong architecture:

- armv7 initramfs on aarch64 kernel (or vice versa)
- Damaged initramfs (try re-downloading)

```sh
# Verify arch
uname -m
file /boot/initramfs    # if accessible
```

### Initramfs not found

```sh
# In GRUB, check the initrd line points to an existing file
ls -la /boot/
# Should show: initramfs  modloop  vmlinuz  ...
```

If the initramfs is missing, re-build it:

```sh
# In build environment
mkinitfs -F "base ata scsi usb cdrom virtio 9p squashfs ext4" \
    -o /out/initramfs-x86_64 7.1.0-0-doki-os-doki-os
```

## Login Issues

### Login prompt doesn't appear

The console may be wrong. Check:

```sh
# In inittab, the getty line should match the console
ttyS0::respawn:/sbin/getty -L 0 ttyS0 vt100    # x86_64
ttyAMA0::respawn:/sbin/getty -L 0 ttyAMA0 vt100  # aarch64, armv7
```

For QEMU, the `-append` should include the same console:

```sh
qemu-system-aarch64 -append "console=ttyAMA0,115200" ...
```

### "Login incorrect" with no password

The `/etc/shadow` file may not have the empty password for root:

```sh
# /etc/shadow
root::0:0:...
```

If it shows `root:!:0:0:...` or `root:$6$...:0:0:...`, the root account is locked. Fix:

```sh
sed -i 's|^root:[^:]*:|root::|' /etc/shadow
```

Or boot to single user mode by adding `init=/bin/sh` to kernel cmdline:

1. In GRUB, press `e` to edit
2. Add `init=/bin/sh` to the linux line
3. Press `Ctrl-X` to boot
4. At the shell prompt:
   ```sh
   mount -o remount,rw /
   sed -i 's|^root:[^:]*:|root::|' /etc/shadow
   sync
   reboot
   ```

### "mdev: unknown user/group 'root:disk'"

The `/etc/passwd` or `/etc/group` is missing or has wrong format. The `/etc/passwd` line for root MUST be:

```
root:x:0:0:root:/root:/bin/bash
```

If it's `root:x:/bin/bash` (missing uid/gid fields), fix:

```sh
sed -i '1s|^.*$|root:x:0:0:root:/root:/bin/bash|' /etc/passwd
```

## Filesystem Issues

### "No space left on device" during boot

The root partition is small. Check:

```sh
df -h
# If 100% full:
# 1. Clean apk cache
apk cache clean
# 2. Remove old kernels (if multiple)
rm -rf /lib/modules/old-*
# 3. Resize the partition (see Storage wiki)
```

### Filesystem corruption

```sh
# Boot to single user mode (init=/bin/sh)
# Then:
mount -o remount,rw /
e2fsck -f /dev/sda2    # or /dev/vda2 for QEMU
reboot
```

### Modloop not found

```sh
# Check boot partition contents
ls /media/*/
# Should show: modloop, initramfs, vmlinuz, ...

# If modloop is missing, re-build
mksquashfs /tmp/rootfs /out/rootfs-x86_64.squashfs \
    -comp xz -b 1M -Xbcj x86 -noappend
cp /out/rootfs-x86_64.squashfs /media/sda1/modloop
```

## Network Issues

### No IP address

```sh
# Check interface state
ip link show
# eth0 should be UP

# If DOWN, bring up
ip link set eth0 up

# Check DHCP
udhcpc -i eth0 -t 5 -n -q -vvv

# If no DHCP server, set static IP
ip addr add 192.168.1.100/24 dev eth0
ip route add default via 192.168.1.1
echo "nameserver 8.8.8.8" > /etc/resolv.conf
```

### DNS not resolving

```sh
# Check /etc/resolv.conf
cat /etc/resolv.conf
# Should have at least one nameserver line

# Test with explicit DNS
nslookup dl-cdn.alpinelinux.org 8.8.8.8

# If empty, restart DHCP
udhcpc -i eth0 -t 5 -n -q
```

### Cloudflared tunnel won't start

```sh
# Check token is valid
echo $TUNNEL_TOKEN

# Try running with debug output
cloudflared tunnel --no-autoupdate run --token "$TUNNEL_TOKEN" --loglevel debug

# Common issues:
# - "tunnel not found" → wrong token
# - "connection refused" → network blocked
# - "no such host" → DNS issue
# - "permission denied" → /etc/doki-tunnel.conf not 0600
```

## SSH Issues

### "Permission denied (publickey)"

The server has `PasswordAuthentication no` and your key isn't authorized:

```sh
# On the DokiOS host (serial console)
mkdir -p /root/.ssh
echo "ssh-ed25519 AAAA... your-key" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
chmod 700 /root/.ssh

# Restart sshd
kill -HUP $(pidof sshd)
```

Or use `ssh-copy-id` from your host:

```sh
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<dokios-ip>
```

### "Connection refused"

sshd is not running or the port is blocked:

```sh
# On DokiOS, check if sshd is running
ps aux | grep sshd
# If not:
/usr/sbin/sshd

# Check port
ss -tlnp | grep 22
# Should show sshd listening on 0.0.0.0:22

# Check firewall
nft list ruleset | grep 22
# If firewall blocks SSH, allow it:
nft add rule inet filter input tcp dport 22 accept
```

### SSH host key verification failed

After re-flashing the image, the host key changes. Fix on client:

```sh
ssh-keygen -R <dokios-ip>    # remove old key
ssh root@<dokios-ip>         # accept new key
```

## Package Management Issues

### `apk update` fails with "Temporary error (try again later)"

DNS or network issue:

```sh
# Check DNS
cat /etc/resolv.conf
nslookup dl-cdn.alpinelinux.org

# Check connectivity
ping -c 3 dl-cdn.alpinelinux.org

# Try with HTTPS explicitly
apk update --repository https://dl-cdn.alpinelinux.org/alpine/edge/main
```

### "Unable to lock database" during `apk add`

Another `apk` process is running. Wait or kill it:

```sh
# Check
ps aux | grep apk

# Kill if stuck
killall apk
```

## Doki Engine Issues

### `doki: command not found`

The Doki binaries are in `/usr/bin/` but PATH is wrong. Fix:

```sh
echo $PATH
# Should include: /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# If missing, set in /etc/profile
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```

### `dokid` won't start

```sh
# Run in foreground to see errors
dokid

# Common issues:
# - Missing /var/run/dokid (create: mkdir -p /var/run/dokid)
# - Missing /etc/doki/config.json (see Configuration wiki)
# - Storage driver not available
```

## Customization Issues

### fastfetch doesn't show skull logo

```sh
# Check config
cat /etc/fastfetch/config.jsonc

# Check logo file
cat /etc/fastfetch/logo.txt

# Run manually
fastfetch --config /etc/fastfetch/config.jsonc
```

### `doki-tunnel` not found after login

The shell didn't load `/etc/profile.d/`. Check:

```sh
ls /etc/profile.d/
# Should include: 00-bashrc.sh  00-dokios.sh  20locale.sh  doki-tunnel.sh

# Run manually
source /etc/profile.d/doki-tunnel.sh
```

### SSH host keys not generated

First boot didn't run `firstboot.sh`. Force it:

```sh
rm -f /etc/dokios-firstboot-done
# Next boot will run firstboot.sh
reboot

# Or run manually
/etc/local.d/firstboot.sh
```

## Build Issues

### `mksquashfs: not found`

```sh
apk add squashfs-tools
```

### `mkinitfs: not found`

```sh
apk add mkinitfs
```

### `grub-install: not found`

```sh
apk add grub
# or for specific arch
apk add grub-bios    # x86_64
apk add grub-efi    # UEFI
```

### Cross-compiler not found

```sh
# Debian/Ubuntu
apt-get install gcc-aarch64-linux-gnu gcc-arm-linux-gnueabihf

# Alpine
apk add aarch64-linux-gnu-gcc arm-linux-gnueabihf-gcc
```

## Getting Help

If this troubleshooting guide doesn't help:

1. **Check the GitHub issues**: <https://github.com/OpceanAI/DokiOS/issues>
2. **Open a new issue** with:
   - Architecture (`uname -m`)
   - Image file (`dokios-0.10.0-{arch}.img`)
   - Boot method (QEMU command, hardware model)
   - Full error message or kernel log
   - Output of `doki version` and `cat /etc/os-release` (if accessible)

3. **Join the discussion**: <https://github.com/OpceanAI/DokiOS/discussions>

For Doki engine issues: <https://github.com/OpceanAI/Doki/issues>
