# Networking

DokiOS uses standard Linux networking with busybox tools. This page covers DHCP, static IPs, WiFi, and the cloudflared tunnel helper.

## Network Configuration

### Default: DHCP

DokiOS runs `udhcpc` on `eth0` at boot (configured in `/etc/inittab`):

```sh
::wait:/bin/busybox udhcpc -i eth0 -t 5 -n -q
```

`udhcpc` (from busybox) requests an IP from the DHCP server, sets up routes, and writes `/etc/resolv.conf`.

### Static IP

Edit `/etc/network/interfaces`:

```sh
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
    address 192.168.1.100/24
    gateway 192.168.1.1
    pre-up echo "nameserver 8.8.8.8" > /etc/resolv.conf
```

Then remove or comment out the `udhcpc` line in `/etc/inittab`:

```sh
# ::wait:/bin/busybox udhcpc -i eth0 -t 5 -n -q
```

Reload with `ifup eth0`.

### Multiple Interfaces

```sh
# /etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

auto eth1
iface eth1 inet static
    address 10.0.0.50/24
```

### Manual Commands

```sh
# Show interfaces
ip addr show
ip link show

# Set IP manually
ip addr add 192.168.1.100/24 dev eth0
ip link set eth0 up

# Add default route
ip route add default via 192.168.1.1

# Test connectivity
ping -c 3 8.8.8.8
ping -c 3 dl-cdn.alpinelinux.org
```

## DNS Configuration

### From DHCP

When `udhcpc` runs, it writes `/etc/resolv.conf`:

```
nameserver 192.168.1.1
search localdomain
```

### Manual

```sh
# Write to /etc/resolv.conf
nameserver 8.8.8.8
nameserver 8.8.4.4
search example.com
```

Or use `resolvconf` (Alpine package):

```sh
apk add openresolv

# Edit /etc/resolvconf.conf
# Then run: resolvconf -u
```

## Cloudflare Tunnel

DokiOS includes `cloudflared` (upstream latest binary) and a helper script `doki-tunnel`.

### Quick Start

```sh
# 1. Get a tunnel token from https://one.dash.cloudflare.com/
#    Create a tunnel, copy the TUNNEL_TOKEN

# 2. Run with token directly
doki-tunnel eyJhIjoiNjE...

# 3. Or set as env var
TUNNEL_TOKEN=eyJhIjoiNjE... doki-tunnel

# 4. Or persist via config file (recommended)
echo 'TUNNEL_TOKEN=eyJhIjoiNjE...' > /etc/doki-tunnel.conf
chmod 600 /etc/doki-tunnel.conf

# 5. On next login, cloudflared auto-starts (because of doki-tunnel.sh)
```

### `doki-tunnel` Script

`/usr/local/bin/doki-tunnel`:

```sh
#!/bin/sh
# Load TUNNEL_TOKEN from config file if env var is not set
if [ -z "$TUNNEL_TOKEN" ] && [ -f /etc/doki-tunnel.conf ]; then
    . /etc/doki-tunnel.conf
fi

TOKEN="${TUNNEL_TOKEN:-${1:-}}"

if [ -z "$TOKEN" ]; then
    cat <<EOF
Usage:
    TUNNEL_TOKEN=xxxxx doki-tunnel
    doki-tunnel xxxxx
    echo 'TUNNEL_TOKEN=xxxxx' > /etc/doki-tunnel.conf
EOF
    exit 1
fi

exec /usr/bin/cloudflared tunnel --no-autoupdate run --token "$TOKEN"
```

### Auto-Start via `/etc/profile.d/doki-tunnel.sh`

```sh
# /etc/profile.d/doki-tunnel.sh
if [ -z "$TUNNEL_TOKEN" ] && [ -f /etc/doki-tunnel.conf ]; then
    . /etc/doki-tunnel.conf
fi

if [ -n "$TUNNEL_TOKEN" ] && [ -x /usr/bin/cloudflared ]; then
    if [ -z "$_DOKI_TUNNEL_STARTED" ]; then
        export _DOKI_TUNNEL_STARTED=1
        if [ -n "$PS1" ]; then
            echo "[DokiOS] Starting Cloudflare tunnel..."
            ( /usr/bin/cloudflared tunnel --no-autoupdate run --token "$TUNNEL_TOKEN" \
                > /var/log/cloudflared.log 2>&1 ) &
        fi
    fi
fi
```

This runs on every interactive login. The `$_DOKI_TUNNEL_STARTED` guard prevents multiple instances.

### Verify tunnel is up

```sh
# Check cloudflared is running
pgrep -f cloudflared

# Check it's connected
cloudflared tunnel info

# Check the metrics endpoint
curl http://localhost:7844/metrics
```

## WiFi (Raspberry Pi)

DokiOS doesn't include `wpa_supplicant` by default. Install it:

```sh
apk add wpa_supplicant
```

Configure `/etc/wpa_supplicant/wpa_supplicant.conf`:

```sh
ctrl_interface=/var/run/wpa_supplicant
update_config=1

network={
    ssid="YourNetwork"
    psk="YourPassword"
    priority=10
}
```

Start WiFi:

```sh
# Start wpa_supplicant in background
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf

# Get IP via DHCP
udhcpc -i wlan0

# Or static
ip addr add 192.168.1.101/24 dev wlan0
ip route add default via 192.168.1.1
```

## Firewall (nftables)

DokiOS includes `nftables` but no rules by default. To enable a basic firewall:

```sh
# Create /etc/nftables.conf
#!/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        # Allow loopback
        iif lo accept

        # Allow established/related
        ct state established,related accept

        # Allow SSH
        tcp dport 22 accept

        # Allow ICMP
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # Allow cloudflared metrics (if used)
        tcp dport 7844 accept
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
```

Apply:

```sh
nft -f /etc/nftables.conf

# Add to /etc/inittab before getty:
::wait:/sbin/nft -f /etc/nftables.conf
```

## Port Forwarding

DokiOS doesn't include a `socat` or `iptables`/`nftables` rule for port forwarding by default. To expose a service:

```sh
# Install socat
apk add socat

# Forward host:8080 → container:80
socat TCP-LISTEN:8080,fork,reuseaddr TCP:172.17.0.2:80 &

# Or use nftables
nft add rule inet nat prerouting tcp dport 8080 dnat to 172.17.0.2:80
nft add rule inet nat postrouting ip saddr 172.17.0.0/16 oif eth0 snat to <host-ip>
```

For complex setups, use the cloudflared tunnel (recommended) or a reverse proxy like `caddy` or `nginx`.

## Network Diagnostics

```sh
# Show all interfaces
ip addr show

# Show routes
ip route show

# Test DNS
nslookup dl-cdn.alpinelinux.org
dig dl-cdn.alpinelinux.org

# Test connectivity
ping -c 3 8.8.8.8
ping -c 3 google.com

# Trace path
traceroute google.com

# Show listening ports
ss -tlnp
netstat -tlnp    # if installed

# Show connections
ss -tnp

# Capture packets
tcpdump -i eth0 -c 10 port 80

# ARP table
ip neigh show
```

## Network Troubleshooting

### No network on boot

1. Check interface is up: `ip link show`
2. Check DHCP got an IP: `ip addr show eth0`
3. Check routes: `ip route show` (should have `default via <gateway>`)
4. Check DNS: `cat /etc/resolv.conf`
5. Test connectivity: `ping 8.8.8.8`

### `udhcpc` fails

```sh
# Run manually with verbose output
udhcpc -i eth0 -vvv

# Check for DHCP server on the network
nmap --script broadcast-dhcp-discover

# Or use static IP as workaround
ip addr add 192.168.1.100/24 dev eth0
ip route add default via 192.168.1.1
```

### Cloudflared fails to start

```sh
# Check the token is valid
cloudflared tunnel --no-autoupdate run --token "$TUNNEL_TOKEN" --loglevel debug

# Common issues:
# - Invalid token: "tunnel not found"
# - Network blocked: "connection refused"
# - DNS issue: "no such host"
```

### DNS not working

```sh
# Check /etc/resolv.conf
cat /etc/resolv.conf

# Test with specific DNS server
nslookup dl-cdn.alpinelinux.org 8.8.8.8

# If empty, restart udhcpc
udhcpc -i eth0 -t 5 -n -q -s /usr/share/udhcpc/default.script
```

## Performance Tuning

### TCP BBR congestion control

```sh
# Add to /etc/sysctl.d/
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
```

### Increase network buffers

```sh
# For high-bandwidth networks
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
```

### Jumbo frames

```sh
# On supported networks
ip link set eth0 mtu 9000
```
