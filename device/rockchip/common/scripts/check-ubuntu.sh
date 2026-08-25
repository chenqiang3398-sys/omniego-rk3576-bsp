#!/bin/bash -e

RK_SCRIPTS_DIR="${RK_SCRIPTS_DIR:-$(dirname "$(realpath "$0")")}"
RK_UBUNTU_ARCH="${RK_UBUNTU_ARCH:-arm64}"
RK_UBUNTU_VERSION="${RK_UBUNTU_VERSION:-noble}"
RK_UBUNTU_MIRROR="${RK_UBUNTU_MIRROR:-http://ports.ubuntu.com/ubuntu-ports}"

if [ "$RK_UBUNTU_ARCH" != arm64 ]; then
	echo "Ubuntu($RK_UBUNTU_VERSION) only supports arm64 in this SDK." >&2
	exit 1
fi

# These host tools form the stable contract used by ubuntu/mk-*.sh.
"$RK_SCRIPTS_DIR/check-package.sh" debootstrap
"$RK_SCRIPTS_DIR/check-package.sh" qemu-aarch64-static \
	qemu-aarch64-static qemu-user-static
"$RK_SCRIPTS_DIR/check-package.sh" mke2fs mke2fs e2fsprogs
"$RK_SCRIPTS_DIR/check-package.sh" sudo

if findmnt -fnu -o OPTIONS -T "$RK_SCRIPTS_DIR" | grep -qE "nodev"; then
	echo "The SDK filesystem is mounted with nodev; chroot cannot be built." >&2
	echo "Remount it with dev support before building Ubuntu." >&2
	exit 1
fi

if ! mke2fs -h 2>&1 | grep -wq -- "-d"; then
	echo "mke2fs does not support populating an image with -d." >&2
	exit 1
fi

if ! [ -r /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
	echo "qemu-aarch64 binfmt registration is unavailable." >&2
	echo "Install/restart binfmt-support and qemu-user-static." >&2
	exit 1
fi

"$RK_SCRIPTS_DIR/check-network.sh" "$RK_UBUNTU_MIRROR" \
	"the Ubuntu ports mirror" \
	"Set RK_UBUNTU_MIRROR to a reachable Ubuntu ports mirror."
