# RK3576 Ubuntu 24.04 rootfs

This directory builds the P1 minimal Ubuntu 24.04 arm64 rootfs. It does not yet install the Rockchip GPU, multimedia, camera, or NPU userspace stacks.

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

The expected module staging directory is normally `output/<board>/kernel-modules`.

## Build the minimal rootfs

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

