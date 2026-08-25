# RK3576 Ubuntu 24.04 rootfs

This directory builds Ubuntu 24.04 arm64 rootfs images for the RK3576 SDK.
The P2 default profile includes Xfce, LightDM and X11. Rockchip GPU,
multimedia, camera and NPU userspace enablement remains a separate P3 task.

## Host dependencies

On an Ubuntu/Debian x86_64 build host:

```bash
sudo apt-get update
sudo apt-get install -y debootstrap qemu-user-static binfmt-support e2fsprogs
```

## Build kernel modules first

Select the same board configuration used by the verified boot image, then run:

```bash
./build.sh kernel-modules
```

For the current board configuration, the module staging directory is
`output/kernel-modules`.

## SDK build entry

The default profile is `desktop`:

```bash
./build.sh ubuntu
```

The build produces the SDK-compatible paths:

```text
output/ubuntu/images/rootfs.ext4
output/firmware/rootfs.img
```

The second path is a relative symlink consumed by the existing `firmware` and
`updateimg` packaging flows.

## P1 compatibility entry

The original minimal-rootfs command remains available for reproducing P1:

```bash
sudo ubuntu/build-minimal-rootfs.sh
```

Optional environment variables:

```text
UBUNTU_MIRROR       Ubuntu ports mirror (default: http://ports.ubuntu.com/ubuntu-ports)
ROOTFS_SIZE_MB      ext4 image size (default: 3072)
ROOTFS_HOSTNAME     target hostname (default: rk3576-ubuntu)
TARGET_USER         initial user (default: linaro)
TARGET_PASSWORD     initial password (default: linaro; change for production)
KERNEL_MODULES_DIR  kernel modules staging root containing lib/modules
```

Output:

```text
output/ubuntu-noble/rootfs.ext4
output/ubuntu-noble/manifests/packages.tsv
output/ubuntu-noble/manifests/rootfs.ext4.sha256
```

This image is intended to be flashed only to the existing `rootfs` partition. Keep the known-good Loader, U-Boot, boot.img, DTB, and parameter image unchanged.

## Script interfaces

The SDK adapter in `device/rockchip/common/scripts/mk-rootfs.sh` calls these
stable interfaces in order:

```text
mk-base-ubuntu.sh <target-dir> [release] [arch] [mirror]
mk-rootfs-noble.sh <target-dir>
mk-image.sh <rootfs-dir> <output-image> [size-mib] [manifest-dir]
```

Do not call the latter two against a mounted or incomplete chroot. All rootfs
builders install cleanup traps so interrupted builds do not leave recursive
`dev`, `proc` or `sys` mounts behind.
