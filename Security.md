# Security

DokiOS is designed for trusted single-tenant deployments (container hosts, edge devices, dev environments). It is not hardened for multi-tenant production by default. This page covers the security baseline and how to harden it further.

## Threat Model

### In Scope

| Threat | Mitigation |
|:-------|:-----------|
| Unauthorized shell access | SSH key-only auth, root password empty by default |
| Network sniffing | TLS for cloudflared, SSH host key fingerprinting |
| Malicious packages from upstream | Alpine's signed package system (`apk verify`) |
| Filesystem corruption | ext4 journal (`CONFIG_JBD2=y`) |
| Boot tampering | Single-partition r/w, no Secure Boot (yet) |
| Container escape | Standard Linux kernel isolation (namespaces, cgroups, seccomp) — provided by Doki engine |

### Out of Scope

| Threat | Why |
|:-------|:----|
| Physical access | DokiOS assumes the operator has physical control of the device |
| Side-channel attacks (Spectre, Meltdown) | Kernel defaults; enable mitigations if needed |
| Supply chain (kernel build) | DokiOS uses Alpine's linux-virt source; trust the build host |
| Zero-day kernel exploits | Not patched in DokiOS 0.10.0 (track Alpine updates) |

## Default Security Posture

### What's Secure by Default

- **No root password**: Login requires SSH key (no brute force)
- **No telnet, no FTP, no rlogin**: Only OpenSSH on port 22
- **Kernel security features enabled**: namespaces, seccomp, AppArmor, Landlock, cgroups v2
- **No unnecessary services**: Only getty on serial console, no daemons
- **No world-writable files**: Standard Alpine file permissions
- **Alpine package signatures**: All `apk add` packages are signed

### What Needs Hardening

- **Open firewall**: All ports are open by default (no `iptables`/`nftables` rules)
- **No automatic security updates**: User must `apk upgrade` manually
- **No audit logging**: `auditd` not installed
- **No integrity checking**: No AIDE or similar
- **No malware scanning**: No ClamAV or similar

## SSH Hardening

### Default `sshd_config`

```sh
Port 22
PermitRootLogin prohibit-password    # Key-only, no password
PubkeyAuthentication yes
PasswordAuthentication no             # No password auth at all
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM no                             # No PAM (simpler, smaller)
```

### Recommended Hardening

```sh
# Generate strong host keys (DokiOS does this on first boot)
ssh-keygen -A

# Add your public key
mkdir -p /root/.ssh
echo "ssh-ed25519 AAAA... your-key" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
chmod 700 /root/.ssh

# Restrict root login to specific keys
echo "PermitRootLogin forced-commands-only" >> /etc/ssh/sshd_config
# Or disable root login entirely
echo "PermitRootLogin no" >> /etc/ssh/sshd_config
# Then create a non-root user
adduser dokios
mkdir -p /home/dokios/.ssh
# ... add their key
```

### Disable Password Authentication Completely

The default is already `PasswordAuthentication no`. To verify:

```sh
grep -i "PasswordAuthentication" /etc/ssh/sshd_config
# PasswordAuthentication no
```

### Restrict Cipher Suites

```sh
# Add to /etc/ssh/sshd_config
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
```

### Disable Root Login via Password

```sh
sed -i 's/^PermitRootLogin prohibit-password/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
# This is the default. Verify it's set.
```

## Firewall Hardening

DokiOS includes `nftables` but no rules by default. To enable a basic firewall:

```sh
# Allow loopback
nft add rule inet filter input iif lo accept

# Allow established/related
nft add rule inet filter input ct state established,related accept

# Allow SSH
nft add rule inet filter input tcp dport 22 accept

# Allow ICMP (ping)
nft add rule inet filter input icmp type echo-request accept

# Allow cloudflared (if used)
nft add rule inet filter input tcp dport 7844 accept  # cloudflared metrics

# Drop everything else
nft add rule inet filter input drop
nft add rule inet filter forward drop

# Save rules
nft list ruleset > /etc/nftables.conf

# Add to /etc/inittab before getty:
::wait:/sbin/nft -f /etc/nftables.conf
```

## Kernel Hardening

### Sysctl Settings

DokiOS has no custom sysctl. To harden, create `/etc/sysctl.d/99-dokios-hardening.conf`:

```sh
# IP forwarding (disable for container host, enable for router)
net.ipv4.ip_forward = 0

# SYN flood protection
net.ipv4.tcp_syncookies = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Don't send ICMP redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Enable reverse path filtering
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Log martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Kernel ASLR (already on by default, but explicit)
kernel.randomize_va_space = 2

# Restrict kernel pointers in /proc
kernel.kptr_restrict = 2

# Restrict dmesg
kernel.dmesg_restrict = 1

# Hide kernel symbols
kernel.printk = 3 3 3 3
```

Then apply:

```sh
sysctl -p /etc/sysctl.d/99-dokios-hardening.conf
```

### Disable Unused Kernel Modules

DokiOS ships with `kmod`. To blacklist modules you don't need:

```sh
# Create /etc/modprobe.d/dokios-blacklist.conf
blacklist firewire-core
blacklist firewire-ohci
blacklist thunderbolt
```

### Secure Boot (Future)

DokiOS does not currently support Secure Boot. To enable:

1. Sign the kernel with your own MOK (Machine Owner Key)
2. Enroll the MOK in UEFI firmware
3. Configure systemd-boot or GRUB to load only signed kernels

This is tracked as a future enhancement.

## Container Security (via Doki)

DokiOS includes Doki v0.10.0 which provides:

### Default Container Isolation

Doki uses the kernel's standard Linux isolation:

- **Namespaces**: PID, network, mount, UTS, IPC, user, cgroup
- **cgroups v2**: Resource limits (CPU, memory, I/O, PIDs)
- **Seccomp-BPF**: 80+ allowed syscalls, blocks dangerous ones
- **AppArmor**: Optional profile per container
- **Capabilities**: Minimal default set, explicit grants

### MicroVM Isolation (Optional)

If KVM is available on the host, Doki can use Firecracker or crosvm for hardware-level isolation. DokiOS 0.10.0 does not include KVM host support (no `/dev/kvm` access in DokiOS by default), but it's available if you enable it.

### Verifying Container Isolation

```sh
# Inside a running container
cat /proc/1/status | grep CapEff
# CapEff: 00000000a80425fb

# This is the bounding set of capabilities.
# Lower = more restricted.

# Check seccomp
grep Seccomp /proc/1/status
# Seccomp: 2  # SECCOMP_MODE_FILTER

# Check namespaces
ls -la /proc/1/ns/
```

## CVE / Security Updates

DokiOS does not have automatic security updates. To stay secure:

1. **Subscribe to Alpine security advisories**: <https://www.alpinelinux.org/posts/>
2. **Manual update cycle**: `apk update && apk upgrade`
3. **Reboot if kernel updated**: New kernel requires reboot
4. **Watch for Doki security advisories**: <https://github.com/OpceanAI/Doki/security>

For automated updates (advanced), use `apk periodic` or a custom script in `inittab`.

## Audit Logging

DokiOS does not include `auditd`. To enable:

```sh
apk add audit
rc-service auditd start    # requires OpenRC, not available in DokiOS
# Or run manually:
auditd
```

For simpler logging, use `syslog-ng` (Alpine default) or just `dmesg` + journald (`systemd-journald` is not available without systemd).

## Secure Configuration Checklist

- [ ] SSH key-based auth enabled (default: yes)
- [ ] Root password empty (default: yes — change if exposing to untrusted networks)
- [ ] Firewall rules defined in `/etc/nftables.conf` (default: no)
- [ ] Sysctl hardening applied (default: minimal)
- [ ] Unused kernel modules blacklisted (default: no)
- [ ] WiFi password in `/etc/wpa_supplicant/wpa_supplicant.conf` is `0600` (manual)
- [ ] `TUNNEL_TOKEN` in `/etc/doki-tunnel.conf` is `0600` (manual)
- [ ] No secrets in shell history (`unset HISTFILE` before pasting secrets)
- [ ] Disk image backed up before major changes

## Reporting Security Issues

For security issues in DokiOS, please email security@anomalyco.com (replace with actual contact) or use GitHub's private vulnerability reporting:

<https://github.com/OpceanAI/DokiOS/security/advisories/new>

For Doki engine issues: <https://github.com/OpceanAI/Doki/security>
