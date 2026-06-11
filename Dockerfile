FROM alpine:3.24

LABEL description="Build environment for Dokios"

RUN apk add --no-cache \
    abuild \
    build-base \
    apk-tools \
    alpine-conf \
    git \
    sudo \
    fakeroot \
    linux-headers \
    bc \
    bison \
    flex \
    elfutils-dev \
    openssl-dev \
    perl \
    python3 \
    bash \
    xorriso \
    syslinux \
    grub \
    grub-efi \
    mtools \
    dosfstools \
    squashfs-tools \
    e2fsprogs \
    cpio

RUN addgroup -S abuild && \
    adduser -S -G abuild -h /home/builder -s /bin/sh builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

RUN mkdir -p /home/builder/.abuild && \
    openssl genrsa -out /home/builder/.abuild/builder.rsa 2048 2>/dev/null && \
    openssl rsa -in /home/builder/.abuild/builder.rsa -pubout \
        -out /home/builder/.abuild/builder.rsa.pub 2>/dev/null && \
    echo 'PACKAGER_PRIVKEY="/home/builder/.abuild/builder.rsa"' > /home/builder/.abuild/abuild.conf && \
    echo 'PACKAGER="DokiOS Builder <builder@doki.opceanai.com>"' >> /home/builder/.abuild/abuild.conf && \
    echo 'REPODEST="/home/builder/packages"' >> /home/builder/.abuild/abuild.conf && \
    chown -R builder:abuild /home/builder/.abuild && \
    cp /home/builder/.abuild/builder.rsa.pub /etc/apk/keys/

WORKDIR /home/builder

USER builder
