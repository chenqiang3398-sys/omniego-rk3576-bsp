#!/bin/bash -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
SDK_DIR="$(realpath "$SCRIPT_DIR/..")"
OUT_DIR="${OUT_DIR:-$SDK_DIR/output/ubuntu-noble}"
ROOTFS_DIR="$OUT_DIR/rootfs"
IMAGE="$OUT_DIR/rootfs.ext4"
MANIFEST_DIR="$OUT_DIR/manifests"

: "${UBUNTU_MIRROR:=http://ports.ubuntu.com/ubuntu-ports}"
: "${ROOTFS_SIZE_MB:=3072}"
: "${ROOTFS_HOSTNAME:=rk3576-ubuntu}"
: "${TARGET_USER:=linaro}"
: "${TARGET_PASSWORD:=linaro}"

if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: Run this script with sudo." >&2
	exit 1
fi

for tool in debootstrap qemu-aarch64-static mke2fs chroot; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "ERROR: Missing host tool: $tool" >&2
		echo "Install: debootstrap qemu-user-static binfmt-support e2fsprogs" >&2
		exit 1
	fi
done

if [ -e "$ROOTFS_DIR" ] || [ -e "$IMAGE" ]; then
	echo "ERROR: Output already exists: $OUT_DIR" >&2
	echo "Move it aside or remove it explicitly before rebuilding." >&2
	exit 1
fi

mkdir -p "$OUT_DIR" "$MANIFEST_DIR"

# P1 compatibility wrapper; the SDK entry uses these same three interfaces.
"$SCRIPT_DIR/mk-base-ubuntu.sh" "$ROOTFS_DIR" noble arm64 "$UBUNTU_MIRROR"
SDK_DIR="$SDK_DIR" UBUNTU_PROFILE=minimal \
	ROOTFS_HOSTNAME="$ROOTFS_HOSTNAME" TARGET_USER="$TARGET_USER" \
	TARGET_PASSWORD="$TARGET_PASSWORD" \
	KERNEL_MODULES_DIR="$KERNEL_MODULES_DIR" \
	"$SCRIPT_DIR/mk-rootfs-noble.sh" "$ROOTFS_DIR"
"$SCRIPT_DIR/mk-image.sh" "$ROOTFS_DIR" "$IMAGE" \
	"$ROOTFS_SIZE_MB" "$MANIFEST_DIR"
