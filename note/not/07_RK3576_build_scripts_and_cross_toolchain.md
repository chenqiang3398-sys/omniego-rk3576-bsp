# 07 RK3576 构建脚本、编译流程与交叉编译工具链

## 1. 总体流程

```text
./build.sh ubuntu
  -> mk-base-ubuntu.sh
  -> configure-target.sh
  -> mk-rootfs-noble.sh
  -> post-rootfs hooks
  -> mk-image.sh
  -> output/ubuntu/images/rootfs.ext4
```
./build.sh ubuntu
        |
        v
选择 RK3576 配置和 Ubuntu 参数
        |
        v
构建 Ubuntu rootfs
        |
        +-- mk-base-ubuntu.sh
        |       debootstrap 创建 Ubuntu 基础系统
        |
        +-- mk-rootfs-noble.sh
        |       安装软件包、模块、固件、overlay
        |
        +-- configure-target.sh
        |       配置用户、网络、LightDM、systemd
        |
        +-- post-rootfs hooks
        |       Rockchip Wi-Fi/BT、权限和系统服务处理
        |
        +-- mk-image.sh
                生成 rootfs.ext4

完整 SDK 流程通常为：

./build.sh all
        |
        +-- mk-loader.sh       编译 U-Boot/SPL
        +-- mk-kernel.sh       编译 Linux 内核和 DTB
        +-- mk-rootfs.sh       构建 Debian/Ubuntu rootfs
        +-- mk-firmware.sh     生成 boot.img、rootfs.img 等
        +-- mk-updateimg.sh    打包 update.img
```

## 2. `build.sh` 总入口

文件：`build.sh`。

它负责读取 RK3576 板卡配置、设置 `RK_CHIP`、`RK_KERNEL_DTS`、`RK_ROOTFS_SYSTEM` 等变量，创建日志并调度 `device/rockchip/common/scripts/` 下的构建脚本。它不是具体编译器，而是 SDK 的统一入口。

常用命令：

```bash
./build.sh lunch          # 选择或查看板卡配置
./build.sh ubuntu         # 构建 Ubuntu rootfs
./build.sh kernel         # 编译 Linux 内核和 DTB
./build.sh kernel-modules # 编译/整理内核模块
./build.sh firmware       # 生成固件镜像
./build.sh updateimg      # 打包 update.img
./build.sh all            # 完整构建
```

## 3. Ubuntu 脚本职责

### 3.1 `mk-base-ubuntu.sh`

文件：`ubuntu/mk-base-ubuntu.sh`。

使用 `debootstrap --foreign` 创建 Ubuntu 24.04 arm64 基础系统，再复制 `qemu-aarch64-static`，通过 chroot 执行 second-stage。开发机通常为 x86_64，目标板为 ARM64，QEMU 解决了开发机不能直接执行 ARM64 用户态程序的问题。

该脚本只负责 Ubuntu 基础文件，不负责内核、设备树、GPU、无线固件和桌面。

### 3.2 `configure-target.sh`

文件：`ubuntu/configure-target.sh`。

在 rootfs chroot 中安装软件包并配置 locale、hostname、`linaro` 用户、SSH、NetworkManager、串口 `ttyFIQ0`、fstab 和 systemd。桌面 profile 会启用 XFCE、LightDM 和 `graphical.target`。LightDM/Xorg 能启动不等于 GPU 已经硬件加速，GPU 用户态库需要单独验收。

### 3.3 `mk-rootfs-noble.sh`

文件：`ubuntu/mk-rootfs-noble.sh`，是 Ubuntu rootfs 主装配脚本。它合并 Ubuntu 基础系统、`manifests/*.packages`、用户和服务、内核模块、Debian 基线固件、Ubuntu overlay 以及 Rockchip post-rootfs hooks。

内核模块从 `output/kernel-modules/lib/modules/` 复制并执行 `depmod`，包括：

```text
aic_load_fw.ko
aic8800_fdrv.ko
aic_btusb.ko
```

AIC8800D80 厂商固件从 `ubuntu/overlay-firmware/vendor/etc/firmware/` 安装到：

```text
/vendor/etc/firmware/  # 厂商驱动请求路径
/lib/firmware/         # Linux 标准路径
```

### 3.4 `mk-image.sh`

文件：`ubuntu/mk-image.sh`。

使用 `mke2fs -d` 将 rootfs 目录制作成 ext4 镜像，生成 `packages.tsv` 和 SHA256 清单，并用 `e2fsck -fn` 做只读一致性检查。输出为 `output/ubuntu/images/rootfs.ext4`。

### 3.5 `build-minimal-rootfs.sh`

这是独立的 rootfs 调试入口，依次调用 `mk-base-ubuntu.sh`、`mk-rootfs-noble.sh`、`mk-image.sh`。`./build.sh ubuntu` 是正式 SDK 集成入口，`sudo ubuntu/build-minimal-rootfs.sh` 适合单独验证 rootfs 脚本。

## 4. 交叉编译工具链

开发机是 x86_64，板子是 aarch64。普通 `gcc` 生成 x86_64 程序，`aarch64-linux-gnu-gcc` 才生成可在板端运行的 ARM64 程序。

### 4.1 Linux 内核

相关文件：`device/rockchip/common/scripts/kernel-helper`、`mk-kernel.sh`。脚本通过 `get_toolchain kernel "$RK_KERNEL_ARCH"` 设置 `RK_KERNEL_TOOLCHAIN`，再导出 `CROSS_COMPILE`。ARM64 通常使用：

```text
ARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-
```

内核 Makefile 会拼接出 `aarch64-linux-gnu-gcc`、`ld`、`ar`、`objcopy`、`strip` 等工具。

### 4.2 U-Boot

`device/rockchip/common/scripts/mk-loader.sh` 获取 `RK_UBOOT_TOOLCHAIN`，调用：

```bash
make.sh CROSS_COMPILE=$RK_UBOOT_TOOLCHAIN
```

U-Boot 与 Linux 可以共用 ARM64 工具链，但使用各自独立的构建系统。

### 4.3 内核模块

AIC8800 属于内核模块，必须与内核保持相同的 `ARCH`、`CROSS_COMPILE` 和内核版本，否则会出现 `Invalid module format`、vermagic 不匹配或 ELF 架构错误。

检查模块架构：

```bash
file output/kernel-modules/lib/modules/6.1.99/kernel/drivers/net/wireless/aic8800/aic_load_fw/aic_load_fw.ko
```

## 5. 哪些步骤需要交叉编译

| 模块 | 是否交叉编译 |
|---|---|
| U-Boot/SPL、Linux、DTB | 是 |
| AIC8800/GPU/NPU 内核模块 | 是 |
| Ubuntu rootfs/debootstrap | 不直接交叉编译，使用 ARM64 包和 QEMU |
| ext4 镜像、update.img | 使用开发机工具制作 |

“构建 Ubuntu rootfs”不等于“交叉编译 Ubuntu”。用户态主要是下载 ARM64 包并配置，真正交叉编译的是启动链、内核、设备树和板级驱动。

## 6. 本项目实际链路

```text
./build.sh ubuntu
  -> debootstrap 创建 Ubuntu 24.04 arm64
  -> apt 安装 XFCE/LightDM/NetworkManager
  -> 复制 6.1.99 内核模块
  -> 复制 AIC8800D80 厂商固件
  -> 执行 post-rootfs hooks
  -> mke2fs 生成 rootfs.ext4
```

内核链路：

```text
./build.sh kernel
  -> 读取 omniego_rk3576_defconfig
  -> ARCH=arm64
  -> CROSS_COMPILE=aarch64-linux-gnu-
  -> 编译 Image、rk3576-omniego.dtb、AIC8800.ko
```

## 7. 秋招项目表述与八股

可表述为：

> 我将 RK3576 原生 Debian 构建链扩展为 Ubuntu 24.04 ARM64 构建链，通过 SDK 入口统一调度 debootstrap、内核交叉编译、模块安装、厂商固件 overlay 和 ext4 镜像制作。针对 AIC8800D80 无线故障，我沿 USB probe、VID/PID 芯片匹配、request_firmware、固件上传和 wlan 接口注册链路定位到固件缺失，并将 U02 固件接入 Ubuntu rootfs。

面试基础知识：

- 驱动运行在内核态，固件是下载到无线芯片内部执行的二进制，NetworkManager/BlueZ 只能管理已经注册成功的设备；模块加载成功不等于无线可用。
- USB 设备通过 VID/PID 匹配驱动，匹配后调用 `.probe()`，拔出时调用 `.disconnect()`。
- `request_firmware()` 按驱动请求的文件名从 rootfs 加载固件；路径、权限、文件名和芯片版本不匹配都会导致失败。
- 无线分层排查顺序是：USB 枚举 -> 内核驱动 -> 固件 -> wlan 接口 -> cfg80211/mac80211 -> NetworkManager -> DHCP。

## 8. 命令环境对照

| 命令/操作 | 环境 |
|---|---|
| `find ubuntu/...`、`rg ...`、`./build.sh ...` | SDK 源码终端 |
| `dmesg`、`lsmod`、`ip`、`rfkill`、`nmcli`、`bluetoothctl` | 板端 Ubuntu 终端 |
| 检查 `ubuntu/binary`、`output/kernel-modules` | SDK 源码终端 |
| 检查 `/vendor/etc/firmware`、`wlan0` | 板端 Ubuntu 终端 |

## 9. 增量构建与快速验证

用户态配置、服务脚本和固件修改时，不必每次重复 debootstrap。可将改动同步到已有 `ubuntu/binary`，再使用 `mk-image.sh` 重新生成 ext4 镜像。内核、DTS 或内核模块源码修改才需要重新编译内核或模块；功能稳定后仍需执行一次完整 `./build.sh ubuntu` 做可复现性确认。

用户态快速流程：

```bash
sudo cp -a ubuntu/overlay/. ubuntu/binary/
sudo mkdir -p ubuntu/binary/vendor/etc/firmware ubuntu/binary/lib/firmware
sudo cp -a ubuntu/overlay-firmware/vendor/etc/firmware/. ubuntu/binary/vendor/etc/firmware/
sudo cp -a ubuntu/overlay-firmware/vendor/etc/firmware/. ubuntu/binary/lib/firmware/
sudo ubuntu/mk-image.sh ubuntu/binary output/ubuntu/images/rootfs.ext4 5120 output/ubuntu/manifests
```

只新增软件包时，可在已有 rootfs 中执行 `sudo chroot ubuntu/binary apt-get install -y wpa-supplicant wireless-regdb rfkill iw usbutils bluez`。增量方式依赖旧 rootfs 状态，只适合开发调试；发布前必须从干净目录完整构建。

## 10. GitHub 分支上传方案

SDK 根目录不是 Git 仓库，代码需要同步到管理仓库 `/home/magine/uisrc/omniego-rk3576-bsp`，目标分支为 `feature/ubuntu-24.04-port`。本阶段只提交 `ubuntu/manifests/base.packages`、`ubuntu/mk-rootfs-noble.sh`、`ubuntu/overlay-firmware/vendor/etc/firmware/*` 以及两份相关笔记；不要提交 `ubuntu/binary/`、`output/ubuntu/`、`output/sessions/` 和生成的镜像。

管理仓库终端执行：

```bash
cd /home/magine/uisrc/omniego-rk3576-bsp
git switch feature/ubuntu-24.04-port
git pull --ff-only origin feature/ubuntu-24.04-port
git status --short
git diff --check
git diff --stat
git add ubuntu/manifests/base.packages ubuntu/mk-rootfs-noble.sh ubuntu/overlay-firmware/vendor/etc/firmware note/not/06_AIC8800D80_firmware_integration_2026-08-28.md note/not/07_RK3576_build_scripts_and_cross_toolchain.md
git commit -m "ubuntu: add AIC8800D80 firmware and rootfs dependencies"
git push origin feature/ubuntu-24.04-port
```

提交前确认固件 SHA256、Shell 语法和构建日志；提交后使用 `git show --stat --oneline HEAD` 留下变更证据。


有办法。你现在每次执行 ./build.sh ubuntu 都会从 rootfs 流程重新开始，包含 debootstrap、软件包安装和镜像制作，所以耗时较长。开发阶段可以采用“分层构建”。
1. 只修改软件包清单时
如果只是修改：
ubuntu/manifests/base.packages
ubuntu/manifests/desktop.packages
不建议每次重新执行完整 ./build.sh ubuntu，可以直接在已有 rootfs 中测试。
在 SDK 源码终端执行：
sudo chroot ubuntu/binary apt-get install -y wpa-supplicant wireless-regdb rfkill iw usbutils bluez
然后重新制作镜像：
sudo ubuntu/mk-image.sh \
    ubuntu/binary \
    output/ubuntu/images/rootfs.ext4 \
    5120 \
    output/ubuntu/manifests
这样跳过 debootstrap，只重新制作镜像。
2. 只修改配置文件或服务脚本时
例如修改：
ubuntu/overlay/etc/X11/xorg.conf.d/20-modesetting.conf
ubuntu/overlay/usr/bin/某个脚本
可以直接复制到已有 rootfs：
sudo cp -a ubuntu/overlay/. ubuntu/binary/
然后制作镜像：
sudo ubuntu/mk-image.sh \
    ubuntu/binary \
    output/ubuntu/images/rootfs.ext4 \
    5120 \
    output/ubuntu/manifests
3. 只修改 AIC8800 固件时
直接同步固件：
sudo mkdir -p ubuntu/binary/vendor/etc/firmware
sudo cp -a ubuntu/overlay-firmware/vendor/etc/firmware/. \
    ubuntu/binary/vendor/etc/firmware/

sudo mkdir -p ubuntu/binary/lib/firmware
sudo cp -a ubuntu/overlay-firmware/vendor/etc/firmware/. \
    ubuntu/binary/lib/firmware/
然后重新生成镜像。
4. 只修改 systemd 服务时
例如修改 Wi-Fi 初始化服务：
sudo cp -a ubuntu/overlay/usr/lib/systemd/system/. \
    ubuntu/binary/usr/lib/systemd/system/
sudo cp -a ubuntu/overlay/usr/bin/. \
    ubuntu/binary/usr/bin/
如果需要设置开机启动：
sudo chroot ubuntu/binary systemctl enable wifibt-init.service
然后重新制作镜像。
5. 不需要重新编译内核的情况
以下修改通常不需要重新编译内核：
Ubuntu 软件包；
Xfce、LightDM、NetworkManager 配置；
Xorg 配置；
Wi-Fi/蓝牙固件；
systemd 服务；
shell 脚本；
/etc 下的配置文件；
用户态测试工具。
只需要更新 rootfs 并重新生成 rootfs.ext4。
6. 必须重新编译内核的情况
以下修改才需要：
./build.sh kernel
DTS/设备树；
内核配置；
AIC8800 驱动源码；
GPU/NPU 内核驱动；
摄像头 sensor 驱动；
USB、MMC、SDIO、UART 等内核驱动；
内核版本或启动参数。
如果还要重新生成完整升级包，再执行：
./build.sh firmware
./build.sh updateimg
7. 建议增加一个快速开发脚本
可以在 SDK 中新增：
ubuntu/update-rootfs-fast.sh
功能是：
同步 overlay
同步 AIC 固件
安装新增软件包
重新生成 rootfs.ext4
以后只修改 Ubuntu 用户态内容时执行：
sudo ubuntu/update-rootfs-fast.sh
这样可以避免重复执行完整 debootstrap。
8. 推荐的开发节奏
修改 Ubuntu 配置/脚本
    -> 快速同步到 ubuntu/binary
    -> mk-image.sh
    -> 烧录 rootfs.ext4
    -> 板端验证
确认用户态功能稳定后，再执行：
./build.sh ubuntu
做一次完整可复现构建。
内核或 DTS 修改时才执行：
./build.sh kernel
./build.sh ubuntu
./build.sh firmware
./build.sh updateimg
简单说：
用户态修改：快速更新 rootfs，不重新 debootstrap
内核/驱动/DTS 修改：重新编译内核
最终发布：完整构建并生成 update.img
