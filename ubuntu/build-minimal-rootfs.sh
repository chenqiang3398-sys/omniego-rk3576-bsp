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

mkdir -p "$ROOTFS_DIR" "$MANIFEST_DIR"

cleanup_chroot_mounts()
{
	for target in dev sys proc; do
		if mountpoint -q "$ROOTFS_DIR/$target"; then
			umount -R "$ROOTFS_DIR/$target" 2>/dev/null || \
				umount -l "$ROOTFS_DIR/$target" 2>/dev/null || true
		fi
	done
}
trap cleanup_chroot_mounts EXIT

echo "Creating Ubuntu 24.04 arm64 base rootfs..."
debootstrap --arch=arm64 --foreign noble "$ROOTFS_DIR" "$UBUNTU_MIRROR"
install -m 0755 "$(command -v qemu-aarch64-static)" \
	"$ROOTFS_DIR/usr/bin/qemu-aarch64-static"

mount -t proc proc "$ROOTFS_DIR/proc"
mount -t sysfs sysfs "$ROOTFS_DIR/sys"
mount --rbind /dev "$ROOTFS_DIR/dev"
mount --make-rslave "$ROOTFS_DIR/dev"

chroot "$ROOTFS_DIR" /debootstrap/debootstrap --second-stage

cat > "$ROOTFS_DIR/etc/apt/sources.list" <<EOF
deb $UBUNTU_MIRROR noble main universe multiverse restricted
deb $UBUNTU_MIRROR noble-updates main universe multiverse restricted
deb $UBUNTU_MIRROR noble-security main universe multiverse restricted
EOF

install -m 0644 "$SCRIPT_DIR/manifests/base.packages" \
	"$ROOTFS_DIR/tmp/base.packages"
install -m 0755 "$SCRIPT_DIR/configure-target.sh" \
	"$ROOTFS_DIR/tmp/configure-target.sh"

ROOTFS_HOSTNAME="$ROOTFS_HOSTNAME" TARGET_USER="$TARGET_USER" \
	TARGET_PASSWORD="$TARGET_PASSWORD" \
	chroot "$ROOTFS_DIR" /tmp/configure-target.sh

if [ -z "$KERNEL_MODULES_DIR" ]; then
	MODULES_PATH="$(find "$SDK_DIR/output" -maxdepth 4 -type d \
		-path '*/kernel-modules/lib/modules' -print -quit 2>/dev/null)"
	if [ -n "$MODULES_PATH" ]; then
		KERNEL_MODULES_DIR="$(dirname "$(dirname "$MODULES_PATH")")"
	fi
fi

if [ -n "$KERNEL_MODULES_DIR" ] && [ -d "$KERNEL_MODULES_DIR/lib/modules" ]; then
	echo "Installing kernel modules from $KERNEL_MODULES_DIR..."
	cp -a "$KERNEL_MODULES_DIR/lib/modules" "$ROOTFS_DIR/lib/"
	for release_dir in "$ROOTFS_DIR"/lib/modules/*; do
		[ -d "$release_dir" ] || continue
		chroot "$ROOTFS_DIR" depmod "$(basename "$release_dir")"
	done
else
	echo "ERROR: No kernel module staging directory found." >&2
	echo "Run ./build.sh kernel-modules and set KERNEL_MODULES_DIR." >&2
	exit 1
fi

for firmware_dir in \
	"$SDK_DIR/debian/binary/lib/firmware" \
	"$SDK_DIR/debian/overlay/lib/firmware"; do
	[ -d "$firmware_dir" ] || continue
	mkdir -p "$ROOTFS_DIR/lib/firmware"
	cp -a "$firmware_dir/." "$ROOTFS_DIR/lib/firmware/"
done

rm -f "$ROOTFS_DIR/usr/bin/qemu-aarch64-static"

chroot "$ROOTFS_DIR" dpkg-query -W \
	-f='${Package}\t${Version}\t${Architecture}\n' \
	> "$MANIFEST_DIR/packages.tsv"

cleanup_chroot_mounts

echo "Creating ext4 image (${ROOTFS_SIZE_MB} MiB)..."
mke2fs -t ext4 -L rootfs -U random -d "$ROOTFS_DIR" \
	-F "$IMAGE" "${ROOTFS_SIZE_MB}M"
sha256sum "$IMAGE" > "$MANIFEST_DIR/rootfs.ext4.sha256"

echo "Ubuntu rootfs image: $IMAGE"
echo "SHA256: $(cut -d' ' -f1 "$MANIFEST_DIR/rootfs.ext4.sha256")"
