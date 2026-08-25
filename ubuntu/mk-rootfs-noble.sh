#!/bin/bash -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
SDK_DIR="${SDK_DIR:-$(realpath "$SCRIPT_DIR/..")}"
source "$SCRIPT_DIR/scripts/common.sh"

# Interface: mk-rootfs-noble.sh <target-dir>
# Required environment from the SDK adapter:
#   UBUNTU_PROFILE, ROOTFS_HOSTNAME, TARGET_USER, TARGET_PASSWORD
#   KERNEL_MODULES_DIR
# Output: a configured rootfs tree ready for Rockchip post-rootfs hooks.
TARGET_ROOTFS_DIR="${1:?Usage: $0 <target-dir>}"
: "${UBUNTU_PROFILE:=desktop}"
: "${ROOTFS_HOSTNAME:=rk3576-ubuntu}"
: "${TARGET_USER:=linaro}"
: "${TARGET_PASSWORD:=linaro}"

require_root

# The second debootstrap stage may remove its bootstrap helper. Validate the
# resulting target ABI and release metadata instead of that temporary file.
if [ ! -x "$TARGET_ROOTFS_DIR/bin/sh" ] || \
	[ ! -r "$TARGET_ROOTFS_DIR/etc/os-release" ] || \
	! grep -qx 'ID=ubuntu' "$TARGET_ROOTFS_DIR/etc/os-release"; then
	echo "ERROR: Invalid Ubuntu base rootfs: $TARGET_ROOTFS_DIR" >&2
	exit 1
fi

case "$UBUNTU_PROFILE" in
	minimal | desktop) ;;
	*) echo "ERROR: Unknown Ubuntu profile: $UBUNTU_PROFILE" >&2; exit 1 ;;
esac

if [ -z "$KERNEL_MODULES_DIR" ]; then
	MODULES_PATH="$(find "$SDK_DIR/output" -maxdepth 4 -type d \
		-path '*/kernel-modules/lib/modules' -print -quit 2>/dev/null)"
	[ -z "$MODULES_PATH" ] || \
		KERNEL_MODULES_DIR="$(dirname "$(dirname "$MODULES_PATH")")"
fi

if [ -z "$KERNEL_MODULES_DIR" ] || \
	[ ! -d "$KERNEL_MODULES_DIR/lib/modules" ]; then
	echo "ERROR: Kernel modules are missing." >&2
	echo "Run ./build.sh kernel-modules or set KERNEL_MODULES_DIR." >&2
	exit 1
fi

trap cleanup_chroot_filesystems EXIT
install_qemu_static
mount_chroot_filesystems

install -D -m 0644 "$SCRIPT_DIR/manifests/base.packages" \
	"$TARGET_ROOTFS_DIR/tmp/ubuntu-packages/base.packages"
if [ "$UBUNTU_PROFILE" = desktop ]; then
	install -D -m 0644 "$SCRIPT_DIR/manifests/desktop.packages" \
		"$TARGET_ROOTFS_DIR/tmp/ubuntu-packages/desktop.packages"
fi
install -m 0755 "$SCRIPT_DIR/configure-target.sh" \
	"$TARGET_ROOTFS_DIR/tmp/configure-target.sh"

ROOTFS_HOSTNAME="$ROOTFS_HOSTNAME" TARGET_USER="$TARGET_USER" \
	TARGET_PASSWORD="$TARGET_PASSWORD" UBUNTU_PROFILE="$UBUNTU_PROFILE" \
	chroot "$TARGET_ROOTFS_DIR" /tmp/configure-target.sh

# Ubuntu owns its desktop policy overlay. Do not import debian/overlay as a
# whole because it also contains Debian-specific packages and service policy.
if [ -d "$SCRIPT_DIR/overlay" ]; then
	echo "Installing Ubuntu rootfs overlay..."
	cp -a "$SCRIPT_DIR/overlay/." "$TARGET_ROOTFS_DIR/"
fi

echo "Installing kernel modules from $KERNEL_MODULES_DIR..."
cp -a "$KERNEL_MODULES_DIR/lib/modules" "$TARGET_ROOTFS_DIR/lib/"
for release_dir in "$TARGET_ROOTFS_DIR"/lib/modules/*; do
	[ -d "$release_dir" ] || continue
	chroot "$TARGET_ROOTFS_DIR" depmod "$(basename "$release_dir")"
done

# Firmware is inherited from the verified vendor Debian baseline in P1.
for firmware_dir in \
	"$SDK_DIR/debian/binary/lib/firmware" \
	"$SDK_DIR/debian/overlay/lib/firmware"; do
	[ -d "$firmware_dir" ] || continue
	mkdir -p "$TARGET_ROOTFS_DIR/lib/firmware"
	cp -a "$firmware_dir/." "$TARGET_ROOTFS_DIR/lib/firmware/"
done

rm -f "$TARGET_ROOTFS_DIR/usr/bin/qemu-aarch64-static"
cleanup_chroot_filesystems

echo "Configured Ubuntu $UBUNTU_PROFILE rootfs: $TARGET_ROOTFS_DIR"
