#!/bin/bash -e

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/scripts/common.sh"

# Interface: mk-base-ubuntu.sh <target-dir> [release] [arch] [mirror]
# Output: a completed Ubuntu debootstrap base tree in <target-dir>.
TARGET_ROOTFS_DIR="${1:?Usage: $0 <target-dir> [release] [arch] [mirror]}"
RELEASE="${2:-noble}"
ARCH="${3:-arm64}"
MIRROR="${4:-http://ports.ubuntu.com/ubuntu-ports}"

require_root

if [ "$ARCH" != arm64 ]; then
	echo "ERROR: Unsupported Ubuntu architecture: $ARCH" >&2
	exit 1
fi

if [ -e "$TARGET_ROOTFS_DIR" ]; then
	echo "ERROR: Target rootfs already exists: $TARGET_ROOTFS_DIR" >&2
	exit 1
fi

trap cleanup_chroot_filesystems EXIT
mkdir -p "$TARGET_ROOTFS_DIR"

echo "Creating Ubuntu $RELEASE $ARCH base rootfs..."
debootstrap --arch="$ARCH" --foreign "$RELEASE" \
	"$TARGET_ROOTFS_DIR" "$MIRROR"

install_qemu_static
mount_chroot_filesystems
chroot "$TARGET_ROOTFS_DIR" /debootstrap/debootstrap --second-stage
cleanup_chroot_filesystems

cat > "$TARGET_ROOTFS_DIR/etc/apt/sources.list" <<EOF
deb $MIRROR $RELEASE main universe multiverse restricted
deb $MIRROR $RELEASE-updates main universe multiverse restricted
deb $MIRROR $RELEASE-security main universe multiverse restricted
EOF

echo "Ubuntu base rootfs: $TARGET_ROOTFS_DIR"
