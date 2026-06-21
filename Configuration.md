# Configuration

DokiOS is configured via files in `/etc` and environment variables. Unlike traditional Linux distros, DokiOS has no central config tool (no `setup-alpine`, no `nixos-rebuild`); you edit files directly.

## Init System: `/etc/inittab`

The `busybox-init` reads `/etc/inittab` on boot:

```sh
::sysinit:/bin/busybox mount -a
::sysinit:/bin/busybox mdev -s
::sysinit:/bin/busybox ip link set lo up
::wait:/bin/busybox ip link set eth0 up
::wait:/bin/busybox udhcpc -i eth0 -t 5 -n -q
::wait:/bin/sh /etc/local.d/firstboot.sh
ttyS0::respawn:/sbin/getty -L 0 ttyS0 vt100
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/busybox umount -a -r
```

### Directives

| Directive | When | Action |
|:----------|:-----|:-------|
| `::sysinit:` | Boot, before any other | Run once before boot runlevel |
| `::wait:` | Boot, after sysinit | Run, wait for completion |
| `::respawn:` | After boot, always | Run, restart on exit |
| `::ctrlaltdel:` | When user presses Ctrl+Alt+Del | Run (usually reboot) |
| `::shutdown:` | On `poweroff`/`reboot` | Run during shutdown |

### Format

```
<id>:<runlevels>:<action>:<command>
```

- `id` — TTY name (e.g. `ttyS0`) or empty
- `runlevels` — Ignored by busybox-init (compatibility)
- `action` — `sysinit`, `wait`, `respawn`, `ctrlaltdel`, `shutdown`
- `command` — Shell command to execute

### Customization Examples

**Disable DHCP for static IP:**

```sh
# Edit /etc/inittab, comment out or remove:
# ::wait:/bin/busybox udhcpc -i eth0 -t 5 -n -q
```

**Run dokid at boot:**

```sh
# Add to /etc/inittab before getty:
::respawn:/usr/bin/dokid > /var/log/dokid.log 2>&1
```

**Add a custom service:**

```sh
::respawn:/usr/local/bin/my-service >> /var/log/my-service.log 2>&1
```

After editing `/etc/inittab`, busybox-init re-reads it on the next `init q` command or reboot:

```sh
init q    # HUP signal to reload
```

## Filesystem: `/etc/fstab`

```sh
UUID=<root-uuid>  /      ext4  rw,relatime  0  1
tmpfs              /var   tmpfs defaults,size=64M  0  0
tmpfs              /tmp   tmpfs defaults,size=32M  0  0
```

### Fields

| Field | Value |
|:------|:------|
| 1. Device | `UUID=<uuid>` or `/dev/sda2` |
| 2. Mount point | `/`, `/var`, `/tmp` |
| 3. Filesystem | `ext4`, `tmpfs`, `vfat` |
| 4. Options | `rw,relatime`, `defaults,size=N` |
| 5. Dump | `0` (disabled) or `1` (enabled) |
| 6. Pass | `0` (no check), `1` (root), `2` (other) |

### Adding a persistent mount

```sh
# Create mount point
mkdir -p /mnt/data

# Add to /etc/fstab
/dev/sda1  /mnt/data  ext4  defaults,noatime  0  2

# Mount
mount /mnt/data
```

## Network: `/etc/network/interfaces`

```sh
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
```

### Static IP

```sh
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 192.168.1.100/24
    gateway 192.168.1.1
    pre-up echo "nameserver 8.8.8.8" > /etc/resolv.conf
```

### WiFi (Raspberry Pi)

DokiOS includes `wpa_supplicant` via `iproute2`. Configure `/etc/wpa_supplicant/wpa_supplicant.conf`:

```sh
ctrl_interface=/var/run/wpa_supplicant
update_config=1

network={
    ssid="YourNetwork"
    psk="YourPassword"
}
```

Then start:

```sh
ifconfig wlan0 up
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
udhcpc -i wlan0
```

## SSH: `/etc/ssh/sshd_config`

Default DokiOS config:

```
Port 22
AddressFamily any
ListenAddress 0.0.0.0
ListenAddress ::

HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no

ChallengeResponseAuthentication no
UsePAM no

PrintMotd yes
PrintLastLog yes
Banner /etc/issue.net
AcceptEnv LANG LC_* TUNNEL_TOKEN

Subsystem sftp /usr/lib/openssh/sftp-server
```

### Customization

**Change port:**

```sh
sed -i 's/^Port 22/Port 2222/' /etc/ssh/sshd_config
```

**Allow password authentication (less secure):**

```sh
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
# Set a password
passwd root
```

**Add SSH public keys:**

```sh
mkdir -p /root/.ssh
echo "ssh-rsa AAAA..." >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
chmod 700 /root/.ssh
```

Or use `ssh-copy-id` from your host:

```sh
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.168.1.100
```

## Cloudflare Tunnel: `/etc/doki-tunnel.conf`

```sh
# /etc/doki-tunnel.conf
# TUNNEL_TOKEN=eyJhIjoiNjE...
```

Mode `0600` (root only). The `doki-tunnel` script reads this file if `TUNNEL_TOKEN` env var is not set.

## DokiOS Identification: `/etc/os-release`

```sh
NAME="DokiOS"
VERSION=0.10.0
ID=dokios
PRETTY_NAME="DokiOS 0.10.0 (Linux 7.1.0)"
HOME_URL="https://github.com/OpceanAI/DokiOS"
SUPPORT_URL="https://github.com/OpceanAI/DokiOS/issues"
BUG_REPORT_URL="https://github.com/OpceanAI/DokiOS/issues"
VENDOR_NAME="Doki"
VENDOR_URL="https://anomalyco.com"
```

## Login Banner: `/etc/issue` and `/etc/motd`

### `/etc/issue` (pre-login)

```
Welcome to \n DokiOS 0.10.0 (Linux \r \m)
Kernel: \r
Arch:   \m
```

### `/etc/motd` (post-login)

Skull ASCII art (replaces Alpine's default).

## Profile Scripts: `/etc/profile.d/`

| File | Purpose |
|:-----|:--------|
| `00-bashrc.sh` | Alpine default, sources `~/.bashrc` |
| `00-dokios.sh` | Runs `fastfetch` with skull logo |
| `20locale.sh` | Alpine default, sets LANG |
| `doki-tunnel.sh` | Auto-starts cloudflared if TUNNEL_TOKEN set |
| `color_prompt.sh.disabled` | Disabled |

## Fastfetch: `/etc/fastfetch/config.jsonc`

```jsonc
{
    "logo": {
        "type": "file",
        "source": "/etc/fastfetch/logo.txt"
    },
    "display": {
        "separator": "─"
    },
    "modules": [
        { "type": "os", "key": "OS       " },
        { "type": "kernel", "key": "Kernel   " },
        { "type": "shell", "key": "Shell    " },
        { "type": "cpu", "key": "CPU      " },
        { "type": "memory", "key": "Memory   " }
    ]
}
```

See [fastfetch docs](https://github.com/fastfetch-cli/fastfetch/wiki) for all options.

## First Boot: `/etc/local.d/firstboot.sh`

Runs on every boot but is idempotent (exits if marker exists). See [Architecture](Architecture#stage-3-busybox-init-dokios-init) for details.

To force re-run:

```sh
rm /etc/dokios-firstboot-done
# Next boot will re-run firstboot.sh
```

## Package Management

DokiOS uses Alpine's `apk` package manager.

```sh
# Update package index
apk update

# Install a package
apk add htop

# Remove a package
apk del htop

# Search for packages
apk search python3

# List installed packages
apk info

# Upgrade all
apk upgrade

# Add a custom repository
echo "https://my-repo.example.com/alpine/v3.24/main" >> /etc/apk/repositories
apk update
```

## Environment Variables

| Variable | Set by | Purpose |
|:---------|:-------|:--------|
| `PATH` | `/etc/profile` | `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin` |
| `EDITOR` | `/etc/profile.d/00-dokios.sh` | `EDITOR=nvim` |
| `PAGER` | `/etc/profile.d/00-dokios.sh` | `PAGER=less` |
| `LANG` | `/etc/profile.d/20locale.sh` | `LANG=en_US.UTF-8` |
| `TUNNEL_TOKEN` | User | Cloudflare tunnel token (used by `doki-tunnel.sh`) |
| `HOME` | busybox-init | `/root` for root user |
| `HOSTNAME` | busybox-init | From `/etc/hostname` |
| `TERM` | getty | `vt100` |

## Customization Persistence

Changes to `/etc/*` files persist across reboots (ext4 is r/w). To make changes permanent:

1. Edit the file
2. Test it
3. Reboot to verify

To make changes part of the image (for redistribution), edit the rootfs during build and re-pack the modloop.

## Default Configuration Reference

| Setting | Value |
|:--------|:------|
| Hostname | `doki-os` |
| Timezone | UTC |
| Locale | `en_US.UTF-8` |
| Root password | (empty) |
| Default shell | `/bin/bash` |
| Console (x86_64) | `ttyS0` 115200 8N1 |
| Console (aarch64, armv7) | `ttyAMA0` 115200 8N1 |
| SSH port | 22 |
| SSH auth | Public key only (root) |
| Network | DHCP on `eth0` |
| DNS | From DHCP |
| Root filesystem | `ext4` r/w |
| `/var`, `/tmp` | `tmpfs` |
| Init system | busybox-init |
| Default services | getty on serial console |
