#!/bin/bash -e

# Interface: mk-image.sh <rootfs-dir> <output-image> [size-mib] [manifest-dir]
# Output: populated ext4 image plus package and SHA256 manifests.
TARGET_ROOTFS_DIR="${1:?Usage: $0 <rootfs-dir> <image> [size-mib] [manifest-dir]}"
IMAGE="${2:?Usage: $0 <rootfs-dir> <image> [size-mib] [manifest-dir]}"
IMAGE_SIZE_MB="${3:-5120}"
MANIFEST_DIR="${4:-$(dirname "$IMAGE")/../manifests}"

if [ "$(id -u)" -ne 0 ]; then
	echo "ERROR: Run mk-image.sh as root." >&2
	exit 1
fi

for target in dev sys proc; do
	if mountpoint -q "$TARGET_ROOTFS_DIR/$target"; then
		echo "ERROR: Refusing to image mounted chroot path: $target" >&2
		exit 1
	fi
done

mkdir -p "$(dirname "$IMAGE")" "$MANIFEST_DIR"
rm -f "$IMAGE"

chroot "$TARGET_ROOTFS_DIR" dpkg-query -W \
	-f='${Package}\t${Version}\t${Architecture}\n' \
	> "$MANIFEST_DIR/packages.tsv"

echo "Creating ext4 image (${IMAGE_SIZE_MB} MiB)..."
mke2fs -t ext4 -L rootfs -U random -d "$TARGET_ROOTFS_DIR" \
	-F "$IMAGE" "${IMAGE_SIZE_MB}M"
e2fsck -fn "$IMAGE"
sha256sum "$IMAGE" > "$MANIFEST_DIR/rootfs.ext4.sha256"

echo "Ubuntu rootfs image: $IMAGE"
echo "SHA256: $(cut -d' ' -f1 "$MANIFEST_DIR/rootfs.ext4.sha256")"
