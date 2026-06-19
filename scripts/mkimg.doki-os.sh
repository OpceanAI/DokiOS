# doki-OS image profiles
# Container-optimized Alpine variant

profile_doki_os_initramfs() {
	title="doki-OS initramfs"
	desc="doki-OS container VM (initramfs-only, no disk)
		Optimized for running containers.
		Includes Doki container engine."
	profile_abbrev="doki"
	image_ext="tar.gz"
	output_format="targz"
	arch="x86_64 aarch64 armv7"
	hostname="doki-vm"

	kernel_flavors="doki-os"
	initfs_features="base ext4 overlay bridge netfilter virtio 9p squashfs wifi"
	initfs_cmdline="modules=loop,squashfs quiet"

	apks="alpine-baselayout alpine-keys alpine-release apk-tools
		busybox busybox-initscripts
		ca-certificates-bundle
		doki-os-base doki-os-kernel
		iproute2 nftables fuse-overlayfs musl
		tini wireless-tools wpa_supplicant udhcpc"
}

profile_doki_os_vm() {
	profile_doki_os_initramfs
	title="doki-OS VM (qcow2)"
	desc="doki-OS container VM with persistent disk
		For use with QEMU, Virtualization.framework, Firecracker."
	image_ext="img.gz"
	output_format="imggz"
	apks="$apks e2fsprogs dosfstools"
}

profile_doki_os_minirootfs() {
	title="doki-OS mini rootfs"
	desc="Minimal doki-OS root filesystem.
		For use in containers and chroots."
	image_ext="tar.gz"
	output_format="rootfs"
	arch="$ARCH"
	rootfs_apks="busybox alpine-baselayout alpine-keys alpine-release
		apk-tools musl-utils doki-os-base"
}

section_doki_overlay() {
	case "$PROFILE" in
		doki_os_initramfs|doki_os_vm) return 0 ;;
		*) return 1 ;;
	esac
}

build_doki_overlay() {
	mkdir -p "$DESTDIR"/etc/doki
	mkdir -p "$DESTDIR"/etc/apk/repositories.d
	mkdir -p "$DESTDIR"/etc/network

	# Config de Doki
	cat > "$DESTDIR"/etc/doki/config.json << 'EOF'
{
	"root": "/var/lib/doki",
	"socket_path": "/var/run/doki.sock",
	"podman_socket_path": "/var/run/podman.sock",
	"cri_socket_path": "/var/run/doki-cri.sock",
	"storage_driver": "overlay2",
	"default_network": "bridge",
	"rootless": false,
	"log_level": "info",
	"dns": { "listen": "127.0.0.11:53" }
}
EOF

	# Repo de doki-OS
	cat > "$DESTDIR"/etc/apk/repositories.d/doki.list << 'EOF'
https://github.com/OpceanAI/DokiOS/releases/download/packages/edge/doki
EOF

	# Network config
	cat > "$DESTDIR"/etc/network/interfaces << 'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

	# WiFi config (wpa_supplicant)
	mkdir -p "$DESTDIR"/etc/wpa_supplicant
	cat > "$DESTDIR"/etc/wpa_supplicant/wpa_supplicant.conf << 'EOF'
ctrl_interface=/var/run/wpa_supplicant
update_config=1
EOF
}
