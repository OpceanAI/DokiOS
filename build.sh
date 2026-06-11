#!/bin/bash
set -e

ARCH="${1:-$(apk --print-arch 2>/dev/null || echo x86_64)}"
PROFILE="${2:-doki_os_initramfs}"
TAG="${3:-$(git rev-parse --short HEAD 2>/dev/null || echo dev)}"

echo "==> Building Dokios for $ARCH (profile: $PROFILE, tag: $TAG)"

# Build packages
echo "==> Building packages..."
for pkg in doki-os-kernel doki dokid doki-compose doki-init doki-kube doki-kubectl doki-os-base doki-os-vm; do
    echo "  -> $pkg"
    cd "doki/$pkg"
    abuild -F checksum 2>/dev/null || true
    abuild -F -r
    cd ../..
done

# Create repository
echo "==> Creating repository..."
REPO_DIR="repo/main/$ARCH"
mkdir -p "$REPO_DIR"
find ~/packages -name '*.apk' -exec cp {} "$REPO_DIR/" \;
cd "$REPO_DIR"
apk index -o APKINDEX.tar.gz *.apk 2>/dev/null || true
abuild-sign -k ~/.abuild/builder.rsa APKINDEX.tar.gz 2>/dev/null || true
cd ../..

# Build image
echo "==> Building image..."
mkdir -p output
./scripts/mkimage.sh \
    --arch "$ARCH" \
    --profile "$PROFILE" \
    --repository "./$REPO_DIR" \
    --repository "https://dl-cdn.alpinelinux.org/alpine/edge/main" \
    --repository "https://dl-cdn.alpinelinux.org/alpine/edge/community" \
    --outdir output/ \
    --tag "$TAG"

echo "==> Done!"
ls -lh output/
