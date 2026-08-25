#!/bin/bash

# Shared chroot lifecycle for Ubuntu rootfs builders.
# Callers set TARGET_ROOTFS_DIR before invoking mount_chroot_filesystems().

require_root()
{
	if [ "$(id -u)" -ne 0 ]; then
		echo "ERROR: Ubuntu rootfs scripts must run as root." >&2
		exit 1
	fi
}

cleanup_chroot_filesystems()
{
	[ -n "$TARGET_ROOTFS_DIR" ] || return 0

	for target in dev sys proc; do
		if mountpoint -q "$TARGET_ROOTFS_DIR/$target"; then
			umount -R "$TARGET_ROOTFS_DIR/$target" 2>/dev/null || \
				umount -l "$TARGET_ROOTFS_DIR/$target" 2>/dev/null || true
		fi
	done
}

mount_chroot_filesystems()
{
	mkdir -p "$TARGET_ROOTFS_DIR/proc" "$TARGET_ROOTFS_DIR/sys" \
		"$TARGET_ROOTFS_DIR/dev"

	mount -t proc proc "$TARGET_ROOTFS_DIR/proc"
	mount -t sysfs sysfs "$TARGET_ROOTFS_DIR/sys"
	mount --rbind /dev "$TARGET_ROOTFS_DIR/dev"

	# Prevent recursive unmounts in the chroot from propagating to the host.
	mount --make-rslave "$TARGET_ROOTFS_DIR/dev"
}

install_qemu_static()
{
	local qemu
	qemu="$(command -v qemu-aarch64-static)"
	install -D -m 0755 "$qemu" \
		"$TARGET_ROOTFS_DIR/usr/bin/qemu-aarch64-static"
}
