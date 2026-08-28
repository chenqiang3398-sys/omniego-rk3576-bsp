# RK3576 Debian 到 Ubuntu 移植学习与秋招面试指南

## 1. 这份笔记怎么用

这份文档不是阶段验收报告，而是面向学习、复盘和求职表达的知识地图。建议分三遍阅读：

1. 第一遍只看第 2～5 章，理解这个项目到底迁移了什么。
2. 第二遍看第 6～9 章，把代码入口、启动流程和故障证据串起来。
3. 第三遍看第 10～14 章，用简历模板和面试题检查自己能否独立讲清楚。

面试时必须区分“已完成”“已验证”和“计划完成”。截至 2026-08-25：

- P0 厂家 Debian 硬件基线已采集；
- P1 Ubuntu 24.04 最小 rootfs 已实机启动并完成串口登录；
- P2 已接入 SDK 构建入口、Xfce/LightDM/X11，并完成 HDMI 无桌面问题定位和板上验证；
- P2 的 Xorg、post-rootfs 权限及错误传递修复已进入代码，最终重编译和重新烧录回归尚未关闭；
- GPU 用户态加速、MPP/RGA 硬解码、Camera/RKAIQ 和 RKNPU 用户态栈仍属于后续阶段。

## 2. 一句话讲清这个项目

在保留 RK3576 厂家 Loader、U-Boot、Linux 6.1 BSP 内核、设备树和烧录布局的前提下，把厂家 Debian 用户空间替换为 Ubuntu 24.04 arm64，并将 Ubuntu rootfs 构建、桌面环境和 SDK 打包流程做成可重复构建、可验证、可继续扩展硬件用户态栈的工程。

它不是：

- 把整个厂家 SDK 换成 Ubuntu 官方 BSP；
- 把 Rockchip 内核换成 Ubuntu generic 内核；
- 找一个论坛 Ubuntu 镜像直接烧录；
- 修改 `/etc/os-release` 假装完成发行版迁移；
- 仅验证“能进入 shell”就宣称 GPU、Camera、NPU 全部可用。

## 3. 先建立正确的系统分层

### 3.1 当前系统组成

```text
BootROM
  |
  v
DDR/Loader/SPL
  |
  v
U-Boot + ATF + OP-TEE
  |
  v
FIT boot.img
  +-- Rockchip Linux 6.1 BSP kernel
  +-- rk3576-omniego DTB
  |
  v
Ubuntu 24.04 arm64 rootfs
  +-- systemd / udev / NetworkManager
  +-- Xorg / LightDM / Xfce
  +-- kernel modules and firmware
  +-- future: Mali / MPP / RGA / RKAIQ / RKNPU userspace
```

这个结构中，Ubuntu 主要替换的是最后一层用户空间。板卡能否从 eMMC 启动、CPU/DDR 是否工作、设备节点是否出现，主要依赖前面的启动链、内核和设备树。

### 3.2 哪些内容保留，哪些内容变化

| 层次 | 本项目策略 | 原因 |
| --- | --- | --- |
| BootROM | 不改 | SoC 固化代码 |
| Loader/DDR | 保留厂家版本 | 与 DDR 参数、启动介质强相关 |
| ATF/OP-TEE | 保留 | 与安全世界和 SoC BSP 配套 |
| U-Boot | 保留已验证版本 | 保持分区、FIT 和烧录链稳定 |
| Linux kernel | 保留 Rockchip 6.1 BSP | Ubuntu generic 内核缺少完整厂商能力 |
| DTB | 保留并按板级硬件维护 | 描述电源、GPIO、总线和外设拓扑 |
| rootfs | Debian 替换为 Ubuntu 24.04 | 统一应用和运维环境 |
| 硬件用户态库 | 分阶段迁移 | 与内核 ABI、发行版 ABI 强耦合 |

### 3.3 为什么不能直接烧 Ubuntu 官方镜像

通用 Ubuntu arm64 镜像并不知道本项目的：

- Rockchip 分区布局和启动地址；
- FIT boot.img 组织方式；
- RK3576 板级 DTB；
- 厂家 GPU、VPU、RGA、ISP、NPU 驱动；
- 专用 firmware、IQ 文件和服务脚本；
- update.img 烧录和升级流程。

因此正确路线是“保留 BSP，替换并适配用户空间”，而不是把 PC/服务器发行版镜像原样烧入开发板。

## 4. Debian 到 Ubuntu 到底难在哪里

Debian 和 Ubuntu 都使用 `dpkg/apt`，但这不代表二进制包可以无条件混用。真正的难点包括：

1. 软件包名称、版本和依赖关系不同；
2. glibc、libstdc++、GStreamer、Mesa 等 ABI 可能不同；
3. 厂家 `.deb` 可能依赖 Debian 特定版本；
4. systemd unit、udev rule 和默认服务策略不同；
5. rootfs 文件所有权和交叉架构 chroot 需要正确处理；
6. GPU、MPP、Camera、NPU 同时包含内核驱动和用户态库；
7. “库能加载”不等于功能、性能和稳定性通过；
8. 构建成功、镜像成功、启动成功、业务成功是四个不同验收层次。

移植的工程价值不只是生成 Ubuntu，而是建立：

- 可重复的 rootfs 构建入口；
- 明确的软件包 manifest；
- 镜像校验和；
- 厂家 Debian Golden Reference；
- 分阶段硬件回归方法；
- 构建失败门禁和问题留痕。

## 5. 本项目的完整实施路线

### 5.1 P0：冻结 Debian Golden Reference

先使用厂家完整 Debian 镜像验证启动链和硬件基线，并采集：

- 内核、DTB、模块、分区和启动参数；
- DRM/GPU 节点及 `eglinfo`；
- MPP/RGA/GStreamer 插件；
- Camera media graph 和 sensor 日志；
- NPU 驱动、库和软件包；
- `dmesg`、journal、失败服务和软件包列表。

为什么必须先做 P0：如果 Ubuntu 上 Camera 不工作，而 Debian 基线中 sensor ID 本来就读取失败，那么它是板级/BSP 已知问题，不能错误归因于 Ubuntu。

### 5.2 P1：最小 Ubuntu rootfs

目标是只证明以下最小闭环：

```text
厂家启动链 -> BSP kernel/DTB -> 挂载 Ubuntu rootfs
             -> systemd -> ttyFIQ0 -> 登录/网络/SSH
```

P1 使用 `debootstrap --foreign` 创建 Ubuntu Noble arm64 根文件系统，再通过 `qemu-aarch64-static` 和 binfmt 在 x86_64 主机完成第二阶段安装。

### 5.3 P2：接入 SDK 和桌面

P2 将临时脚本变成 SDK 正式能力：

- 增加 Ubuntu Kconfig；
- 支持 `./build.sh ubuntu`；
- 拆分 base、rootfs 配置和 ext4 镜像脚本；
- 复用 kernel modules 和 post-rootfs 生命周期；
- 输出 SDK 约定的 `rootfs.ext4` 和 `rootfs.img`；
- 默认安装 Xfce、LightDM、X11；
- 记录软件包 manifest 和 SHA256。

### 5.4 P3 以后：硬件用户态栈

推荐顺序：

```text
DRM/KMS -> Mali GPU -> RGA -> MPP/GStreamer
        -> Camera/RKISP/RKAIQ -> RKNPU -> 并发稳定性
```

原因是后面的图形、多媒体和 AI 测试通常依赖前面的显示、内存、DMA 和基础用户态环境。

## 6. 代码入口地图

### 6.1 SDK 配置入口

```text
device/rockchip/common/configs/Config.in.ubuntu
device/rockchip/common/configs/Config.in.rootfs
```

核心变量：

```text
RK_ROOTFS_SYSTEM=ubuntu
RK_UBUNTU_VERSION=noble
RK_UBUNTU_ARCH=arm64
RK_UBUNTU_PROFILE=desktop
RK_UBUNTU_IMAGE_SIZE_MB=5120
```

### 6.2 Ubuntu 构建分层

```text
ubuntu/mk-base-ubuntu.sh
    负责 debootstrap base rootfs

ubuntu/mk-rootfs-noble.sh
    负责软件包、用户、服务、modules、firmware、overlay

ubuntu/mk-image.sh
    负责 package manifest、ext4、e2fsck、SHA256
```

SDK 适配函数位于：

```text
device/rockchip/common/scripts/mk-rootfs.sh: build_ubuntu()
```

它的输出契约是：

```text
output/ubuntu/images/rootfs.ext4
output/firmware/rootfs.img
```

### 6.3 目标系统配置

```text
ubuntu/configure-target.sh
ubuntu/manifests/base.packages
ubuntu/manifests/desktop.packages
ubuntu/overlay/
```

`configure-target.sh` 在 chroot 内执行，负责 locale、hostname、用户、SSH、NetworkManager、LightDM、systemd target 和 fstab。

## 7. 必须掌握的基础知识

### 7.1 什么是 rootfs

rootfs 是 Linux 启动后挂载为 `/` 的文件系统，包含：

- `/bin`、`/usr/bin`：用户命令；
- `/lib`、`/usr/lib`：动态库和运行时；
- `/etc`：系统配置；
- `/lib/modules`：可加载内核模块；
- `/lib/firmware`：设备固件；
- systemd、udev、shell、apt 和业务程序。

内核不是 rootfs 的一部分。本项目的内核位于 boot.img，Ubuntu 替换主要发生在 rootfs 分区。

### 7.2 内核驱动、用户态库和 firmware 的区别

以 GPU 为例：

```text
应用/OpenGL ES
    |
用户态 EGL/GLES/Mali 库
    |
ioctl + /dev/mali0 或 render node
    |
内核 Mali 驱动
    |
GPU 硬件
```

只有 `/dev/mali0` 说明内核驱动 probe 成功，不代表 EGL/GLES 用户态库正确。反过来，库文件存在也不代表它与内核 DDK 匹配。

firmware 是由 CPU 在设备初始化时加载到 Wi-Fi、VPU、NPU 等硬件内部运行的二进制，不等同于 Linux 驱动模块。

### 7.3 什么是 BSP

BSP 即 Board Support Package，通常包含：

- Bootloader；
- 厂商内核和补丁；
- 板级 DTS；
- 驱动和 firmware；
- 硬件用户态库；
- 镜像制作、烧录和测试工具。

发行版负责通用用户空间，BSP 负责让特定 SoC 和板卡工作。嵌入式 Linux 项目经常是“厂商 BSP + 某个发行版用户空间”的组合。

### 7.4 什么是设备树

设备树描述不可自动枚举硬件，包括：

- 寄存器地址和中断；
- GPIO、时钟、reset；
- regulator 电源关系；
- I2C/SPI 设备地址；
- MIPI lane 和 endpoint graph；
- status 是否启用。

驱动代码描述“如何控制某类设备”，DTS 描述“这块板上有什么设备、连接在哪里”。Camera、显示和电源问题经常需要同时检查驱动与 DTS。

### 7.5 debootstrap、chroot 和 QEMU binfmt

`debootstrap` 用 Debian/Ubuntu 软件包构造最小根文件系统。x86_64 主机不能直接执行 arm64 ELF，因此采用两阶段方式：

1. `--foreign` 在主机解包 arm64 软件包；
2. 把 `qemu-aarch64-static` 放入 rootfs；
3. 注册 binfmt，让内核遇到 arm64 ELF 时交给 QEMU；
4. `chroot` 进入目标根目录完成配置。

chroot 只改变进程看到的根目录，不是虚拟机，也不是安全容器。它仍共享宿主机内核。

### 7.6 交叉编译和用户态模拟的区别

- 交叉编译：x86_64 上的交叉编译器生成 arm64 代码；
- QEMU user mode：在 x86_64 上解释执行已经生成的 arm64 用户程序；
- 板上原生编译：arm64 CPU 自己运行 arm64 编译器。

内核和驱动通常交叉编译；rootfs 内的 `dpkg` maintainer scripts 常通过 QEMU user mode 执行。

### 7.7 kernel module 与 depmod

模块必须放在：

```text
/lib/modules/$(uname -r)/
```

目录版本必须与目标内核 `uname -r` 精确匹配。`depmod` 根据模块依赖和符号生成 `modules.dep`、`modules.alias` 等索引。版本不一致常见结果是：

```text
Invalid module format
version magic mismatch
Unknown symbol
```

### 7.8 systemd target 与显示管理器

- `multi-user.target`：类似传统字符模式；
- `graphical.target`：在 multi-user 基础上启动图形登录；
- LightDM：显示管理器，负责启动 Xorg、greeter 和用户会话；
- Xorg：显示服务器；
- Xfce：桌面环境。

`Reached graphical.target` 不等于桌面一定可见。systemd target 到达后，LightDM 或 Xorg 仍可能立即失败，必须检查服务状态和 Xorg 日志。

### 7.9 DRM/KMS 基础

DRM/KMS 是 Linux 显示子系统：

- connector：HDMI、DP、DSI 等物理输出；
- encoder：把像素流编码为接口信号；
- CRTC：扫描输出时序；
- plane：图层；
- framebuffer：像素缓冲区。

常用诊断：

```bash
cat /sys/class/drm/card*-*/status
cat /sys/class/drm/card*-*/modes
sudo cat /sys/kernel/debug/dri/0/state
```

HDMI `connected` 且 modes 非空，说明 HPD 和 EDID 基本正常；CRTC `active=1` 才说明已经完成 modeset。

### 7.10 Linux UID/GID 与镜像所有权

rootfs 中 `/etc/shadow`、systemd 私有目录和用户 home 必须保留正确 UID/GID。不能为了让构建脚本可写，就简单执行：

```bash
chown -R current-user rootfs/
```

否则制作进镜像后，系统文件会错误地属于普通用户。正确做法是让需要修改目标 rootfs 的阶段在受控 root 权限下运行，最后校正构建输出和 home 目录所有权。

### 7.11 ext4 镜像为什么还要 e2fsck 和 SHA256

- `mke2fs -d`：把 rootfs 目录填充到 ext4 镜像；
- `e2fsck -fn`：只读检查 inode、目录、引用计数和 group summary；
- SHA256：确认传输、归档和烧录使用的是同一制品；
- package manifest：回答镜像内到底安装了哪些版本。

文件存在不等于文件系统一致，命令退出 0 也不等于所有 post hook 都执行成功。

## 8. 本项目最有价值的故障案例

### 8.1 chroot 残留挂载导致无法删除 rootfs

现象：

```text
rm: cannot remove 'rootfs/dev': Device or resource busy
```

根因：构建中断后，`/dev` 的 rbind、`/proc` 或 `/sys` 仍挂载在 chroot 中。

解决：统一封装 mount/cleanup，使用 EXIT trap，并对 `/dev` 设置 `--make-rslave`，避免递归挂载传播。

知识点：挂载点不是普通目录；`rm -rf` 不能代替 `umount`；bind mount 和 mount namespace 是嵌入式 rootfs 构建常见考点。

### 8.2 rootfs 能生成，但 post-rootfs 实际失败

现象：Wi-Fi/蓝牙钩子创建 `/system` 时 `Permission denied`，外层却继续输出镜像。

根因有两层：

1. debootstrap rootfs 保留目标 UID/GID，普通 SDK 用户无权写系统目录；
2. 钩子调度使用 `if ! command; then ret=$?`，`!` 把失败状态取反，进入分支后的 `$?` 变成 0。

修复：

- 参考厂家 Debian 流程，以 root 执行 target-side post-rootfs；
- 使用 `if command; then ... else ret=$?` 保留真实退出码；
- privileged Kbuild 后恢复 `external/rkwifibt` 的 SDK owner；
- Ubuntu 输出清理和 manifest 目录分别处理，保证下一次增量构建可删除。

面试亮点：不仅修复权限，还发现“构建系统假成功”的可靠性缺陷，并建立失败门禁。

### 8.3 HDMI 已连接但没有桌面

第一步没有直接改 DTS，而是分层排查：

1. sysfs 显示 HDMI `connected`；
2. EDID 能得到 1440p、1080p 等 modes；
3. DRM state 显示 HDMI 绑定 `video_port0`，`1920x1080@60` 且 active；
4. 因此排除线缆、HPD、DDC、PHY 和内核 modeset；
5. `systemctl status lightdm` 显示服务失败；
6. Xorg 日志报告多个 framebuffer/DRM 设备选择异常。

系统中：

```text
/dev/dri/card0 -> Rockchip VOP2 display DRM
/dev/dri/card1 -> RKNPU DRM/GEM device
```

Xorg 自动选卡失败。通过 Xorg `OutputClass` 设置 Rockchip 为 PrimaryGPU，并用 `kmsdev=/dev/dri/card0` 明确绑定后，LightDM/Xfce 在 HDMI 上显示成功。

面试亮点：通过证据逐层缩小范围，而不是把所有“无画面”都归因于 HDMI 驱动或设备树。

### 8.4 SSH 首次启动 host key 顺序

镜像发布前会删除构建机生成的 SSH host key，目标板首次启动时再生成。systemd override 必须先执行 `ssh-keygen -A`，再执行 `sshd -t`；顺序错误会导致 sshd 在密钥不存在时校验失败。

知识点：镜像不能复制构建机身份密钥；首次启动初始化必须可重复且顺序明确。

### 8.5 PARTUUID 与根分区

内核通过 bootargs 中的 `root=PARTUUID=...` 找到根分区。PARTUUID 写错、被截断或与 parameter 分区布局不一致，会在进入用户空间前失败。

排查要区分：

- 内核是否识别 eMMC；
- 分区是否存在；
- root 参数是否匹配；
- ext4 是否完整；
- `/sbin/init` 是否存在并能执行。

## 9. 一套可复用的排查方法

### 9.1 先定义故障发生在哪一层

```text
不上电
  -> 电源/硬件

没有 Loader/U-Boot 日志
  -> BootROM/Loader/串口

U-Boot 正常但 kernel 不启动
  -> boot.img/FIT/地址/DTB

kernel 启动但挂载 rootfs 失败
  -> 分区/root 参数/ext4/驱动

systemd 启动但服务失败
  -> rootfs 包、配置、权限、依赖

设备节点存在但功能失败
  -> 用户态库/ABI/firmware/业务参数
```

### 9.2 证据优先于猜测

每次排查至少回答：

1. 期望行为是什么？
2. 最后一个成功节点是什么？
3. 第一个明确失败节点是什么？
4. 哪条日志直接支持根因？
5. 如何做最小改动验证？
6. 如何把手工验证固化为可重复构建？

### 9.3 四级成功标准

| 等级 | 含义 | 示例 |
| --- | --- | --- |
| L1 | 生成制品 | `rootfs.ext4` 存在 |
| L2 | 制品完整 | SHA256、e2fsck 通过 |
| L3 | 系统启动 | systemd、串口、网络正常 |
| L4 | 功能验收 | 桌面/GPU/硬解码/Camera/NPU 通过实测 |

面试时说明自己如何避免把 L1 当成 L4，会比只罗列命令更有说服力。

## 10. 简历怎么写

### 10.1 推荐项目名称

```text
RK3576 嵌入式 Linux BSP 与 Ubuntu 24.04 系统移植
```

或者：

```text
基于 Rockchip RK3576 的 Ubuntu 24.04 rootfs 构建与硬件适配
```

### 10.2 当前阶段可用的简历描述

以下写法严格对应当前 P0～P2 事实：

> 基于 RK3576 厂家 Linux 6.1 BSP，将 Debian 用户空间迁移至 Ubuntu 24.04 arm64；保留 Loader/U-Boot/FIT boot.img/DTB 和分区布局，使用 debootstrap、QEMU binfmt 与 chroot 构建目标 rootfs，实现串口登录、systemd、网络和 SSH 启动闭环。

> 为 Rockchip SDK 增加 Ubuntu Kconfig、`./build.sh ubuntu`、分层 rootfs 脚本、Xfce/LightDM/X11 桌面配置及 ext4/manifest/SHA256 产物，复用 kernel modules、post-rootfs 和 firmware 打包流程。

> 定位 HDMI 无桌面问题：通过 HPD/EDID、DRM connector/CRTC state 排除硬件链，进一步从 Xorg 日志发现 VOP2 与 RKNPU 多 DRM 设备选卡冲突，通过 PrimaryGPU 和 `kmsdev=/dev/dri/card0` 完成板上验证；同时修复 post-rootfs 权限与 shell 退出码被吞导致的构建假成功问题。

不要在当前阶段写：

```text
完成 GPU、4K 硬解码、Camera、NPU 全功能移植
```

因为这些能力尚未完成 Ubuntu 用户态栈和稳定性回归。

### 10.3 后续完成 P3～P7 后可以补充的量化项

只有拿到真实测试数据后再写：

- GPU：EGL renderer、glmark2 分数、持续运行时间；
- 解码：H.264/H.265/AV1 分辨率、帧率、CPU 占用；
- Camera：sensor 型号、分辨率、帧率、丢帧和 3A；
- NPU：模型、FPS/时延、精度对比、功耗；
- 稳定性：冷启动次数、72 小时并发压力、失败率。

### 10.4 STAR 项目故事

Situation：厂家只提供 Debian 完整镜像，但项目上层应用和交付环境要求 Ubuntu 24.04，同时必须保留 RK3576 的专用硬件能力。

Task：建立可重复构建的 Ubuntu rootfs，接入原 SDK 打包流程，并保证启动、桌面以及后续 GPU/多媒体/Camera/NPU 的迁移基础。

Action：先采集 Debian Golden Reference，再分 P1/P2 逐层实现；使用 debootstrap + QEMU 构建 arm64 rootfs，集成 modules/firmware/systemd；增加 SDK Ubuntu 入口和构建门禁；利用串口、systemd、DRM sysfs/debugfs、Xorg 日志定位权限、挂载、显示和错误传递问题。

Result：Ubuntu 24.04 已完成最小启动、串口登录和 HDMI/Xfce 板上验证；SDK 已具备 Ubuntu 构建入口、manifest 和镜像校验；发现并修复 post-rootfs 假成功和多 DRM 选卡问题，为后续全硬件用户态栈迁移建立可追溯基线。

## 11. 自我介绍话术

### 11.1 一分钟版本

我做过一个 RK3576 的嵌入式 Linux 系统移植项目。项目不是简单烧一个 Ubuntu 镜像，而是保留厂家 Loader、U-Boot、Linux 6.1 BSP 内核和设备树，只把 Debian 用户空间迁移到 Ubuntu 24.04。前期我先采集厂家 Debian 的 GPU、多媒体、Camera、NPU 和系统基线，然后用 debootstrap、QEMU binfmt 和 chroot 构建 arm64 rootfs，再把 Ubuntu 接入原 SDK 的 Kconfig、build.sh、post-rootfs 和镜像打包流程。目前完成了最小启动、网络、SSH、Xfce/LightDM 和 HDMI 显示验证。过程中我定位过 chroot 挂载泄漏、rootfs 权限、shell 错误码丢失以及 RKNPU 和显示 DRM 多设备导致 Xorg 选卡失败等问题。后续正在按 GPU、硬解码、Camera、NPU 的顺序做用户态栈适配和稳定性回归。

### 11.2 三分钟版本的展开顺序

1. 业务为什么要求 Ubuntu；
2. 为什么保留 Rockchip BSP 内核；
3. P0/P1/P2 如何拆阶段；
4. 讲一个构建系统问题；
5. 讲一个 HDMI/Xorg 问题；
6. 说明当前边界和后续计划。

不要从“我先执行了某某命令”开始。先讲架构选择和问题边界，再讲命令作为证据。

## 12. 高频面试题与参考回答

### 12.1 Debian 和 Ubuntu 有什么关系，为什么还要移植

Ubuntu 基于 Debian，二者都使用 dpkg/apt，但发行周期、仓库版本、默认配置和 ABI 组合不同。上层应用可能更偏向 Ubuntu 生态，而 Rockchip BSP 用户态包可能针对 Debian 构建，所以仍需重建 rootfs、处理依赖和重新验证硬件用户态栈。

### 12.2 为什么不换 Ubuntu 内核

通用 Ubuntu 内核不一定包含与当前 SDK 配套的 RK3576 GPU、VPU、ISP、NPU、RGA 和板级补丁。保留已验证 BSP 内核可以缩小变量，先完成用户空间迁移，再逐项验证硬件能力。

### 12.3 内核启动后如何找到 rootfs

U-Boot 把 bootargs 传给内核，其中 `root=PARTUUID=...` 指定根分区。内核初始化存储控制器和 ext4 驱动后挂载根分区，再执行 `/sbin/init`，本项目中是 systemd。

### 12.4 initramfs 和 rootfs 有什么区别

initramfs 是内核启动早期位于内存中的临时根文件系统，用于加载存储、解密、RAID 等能力并切换到真正 rootfs。产品 rootfs 是最终挂载为 `/` 的持久文件系统。本项目当前 boot 路径可以直接挂载 eMMC ext4 rootfs。

### 12.5 为什么要挂载 proc、sys、dev

chroot 内的软件包脚本可能需要进程信息、sysfs 设备信息和 `/dev` 节点。`proc`、`sysfs` 和 `/dev` 不是普通静态目录，需要在 chroot 生命周期中显式挂载并可靠卸载。

### 12.6 为什么 `/dev` 常用 rbind

`--rbind` 会递归绑定 `/dev` 及其子挂载，例如 `/dev/pts`。配合 `--make-rslave` 可以防止 chroot 侧的挂载变化向宿主传播。

### 12.7 什么是动态链接器 ABI 问题

程序启动时由 ELF interpreter 加载依赖库。即使库文件名相同，所需符号版本或结构体 ABI 不一致也会导致 `version not found`、undefined symbol 或运行崩溃。不能仅用强制安装 Debian 包证明 Ubuntu 兼容。

### 12.8 如何判断视频是否硬解码

不能只看“能播放”。需要确认 GStreamer/FFmpeg 实际插件或 MPP 工具、VPU 设备节点和内核日志，同时观察 CPU 占用、帧率、掉帧以及 MPP/IOMMU/reset 错误。

### 12.9 如何判断 GPU 是否硬件加速

检查 `/dev/mali0` 或 render node、EGL vendor/renderer、加载的 Mali 用户态库和 `eglinfo`；运行 glmark2 并观察 CPU、性能和内核 GPU 日志。renderer 为 llvmpipe/softpipe 表示软件渲染。

### 12.10 DTS 中 status=okay 是否代表设备一定工作

不代表。它只允许驱动 probe，还需要 compatible 匹配、资源正确、电源时序、时钟、reset、GPIO、总线通信和外设本身正常。

### 12.11 probe defer 是什么

驱动依赖的 regulator、clock、GPIO controller 等尚未就绪时可以返回 `-EPROBE_DEFER`，内核稍后重试。持续 defer 通常说明依赖节点缺失或驱动未加载。

### 12.12 什么是 IOMMU fault

设备 DMA 访问了未映射或权限错误的 IOVA。常见原因包括 buffer 生命周期错误、用户态/驱动版本不匹配、错误的 DMA 地址或并发同步问题。不能只重启服务掩盖，需要保存 fault 地址、设备、页表和调用场景。

### 12.13 为什么模块版本必须匹配 uname -r

模块包含 vermagic 和内核符号依赖。配置、编译器选项或内核版本不一致可能导致 ABI 不兼容，内核会拒绝加载或出现 Unknown symbol。

### 12.14 为什么 LightDM started 仍可能没桌面

systemd 的 started 只表示进程曾成功拉起。LightDM 随后启动 Xorg，如果 Xorg 选卡、权限、驱动或配置失败，LightDM 可能快速退出并重试。应检查当前 active 状态、journal 和 `/var/log/lightdm/x-0.log`。

### 12.15 card0 为什么不一定永远是显示设备

DRM minor 按驱动注册顺序分配，多个 DRM/GEM 驱动可能改变编号。当前板上 Rockchip display 是 card0、RKNPU 是 card1，因此用已验证配置绑定 card0；更稳健的长期方案还应结合 MatchDriver、udev symlink 或设备路径验证，避免仅凭编号猜测。

### 12.16 shell 中 `if ! cmd; then ret=$?` 有什么问题

`!` 会对命令退出状态取反。原命令失败时，条件整体成功，进入 then 后 `$?` 是取反后的 0，原始错误码已经丢失。应使用 `if cmd; then ... else ret=$?; ... fi`。

### 12.17 为什么不能把 rootfs 全部 chown 给构建用户

文件 UID/GID 会被写入最终镜像。系统文件属于 UID 1000 会造成权限和安全问题。应在受控 root 权限下修改目标树，再恢复 SDK 输出/源码所有权，并单独保留用户 home 的 UID。

### 12.18 如何做到可重复构建

固定发行版、镜像源、包清单、BSP commit 和构建配置；避免手工进入 rootfs 修改；输出 package manifest 和 SHA256；构建失败立即停止；保存日志；使用同一测试素材和回归命令。

### 12.19 为什么要保留 Debian Golden Reference

它能回答问题是板级硬件/BSP 原本就存在，还是 Ubuntu 迁移引入。还可对比软件包、库、firmware、设备节点、性能和内核日志，缩短定位路径。

### 12.20 交叉编译工具链由哪些部分组成

编译器、汇编器、链接器、目标架构 sysroot、头文件和目标库。工具链三元组描述目标架构、厂商和 ABI，例如 aarch64 Linux GNU。

### 12.21 静态链接和动态链接的取舍

静态链接部署简单但体积大、升级和许可证管理复杂，也无法覆盖所有驱动插件场景；动态链接节省空间并便于共享升级，但依赖 ABI、搜索路径和版本管理。BSP 图形、多媒体栈通常依赖动态库和插件。

### 12.22 udev 的作用是什么

接收内核 uevent，根据规则创建设备节点、设置权限、符号链接并触发服务。设备节点权限、稳定命名和热插拔问题常需要检查 udev rule。

### 12.23 systemd service 常见排查命令

```bash
systemctl status SERVICE --no-pager -l
journalctl -b -u SERVICE --no-pager
systemctl cat SERVICE
systemctl show SERVICE
systemd-analyze critical-chain
```

### 12.24 如何设计镜像发布门禁

至少包括：构建零错误、hook 全通过、包清单、SHA256、e2fsck、无残留挂载、串口启动、失败服务检查、网络/SSH、目标硬件功能回归和版本记录。

### 12.25 如果面试官问“你最大的收获是什么”

可以回答：学会把嵌入式 Linux 问题按启动链、内核、设备树、rootfs、系统服务和硬件用户态栈分层；用可验证证据找到第一个失败点；把板上手工修复回写到构建系统，并用失败门禁防止相同问题重新进入镜像。

## 13. 面试官可能继续追问什么

### 13.1 为什么 Xorg 配置暂时禁用加速

P2 目标是验证显示服务器和桌面闭环，Mali 用户态栈尚未迁移。使用软件渲染可以隔离 Xorg 选卡与 GPU ABI 两类变量。P3 再改为 glamor，并通过 EGL renderer 和性能测试验收。

### 13.2 为什么 Wi-Fi 钩子会创建 Android 风格目录

Rockchip 厂家脚本需要兼容多种 rootfs，部分工具和 firmware 查找路径沿用了 `/system`、`/vendor` 布局。Ubuntu 适配时需要确认这些兼容链接是否必要，不能看到 Android 路径就直接删除。

### 13.3 为什么 rootfs.img 是符号链接

SDK 的 firmware 打包流程消费统一路径 `output/firmware/rootfs.img`，实际 rootfs 系统可能是 Buildroot、Debian、Yocto 或 Ubuntu。相对符号链接让上层打包流程与具体构建后端解耦。

### 13.4 为什么不一开始就迁移所有硬件库

变量过多会导致问题无法归因。先稳定启动和系统服务，再显示、GPU、多媒体、Camera、NPU，能够让每一阶段都有明确输入、输出和回滚点。

### 13.5 如何处理闭源库

记录来源、版本、SHA256、许可证、适配的内核/DDK 版本和依赖；尽量不覆盖 Ubuntu 核心库；通过私有 deb 包和仓库发布；建立升级和回滚矩阵。

## 14. 简历和面试中的常见错误

### 14.1 把“烧录镜像”写成“系统移植”

系统移植应能解释启动链、rootfs 生成、内核/用户态边界、驱动适配和验证方法。只会运行烧录工具不足以支撑该表述。

### 14.2 只说用了哪些工具，不说为什么

比起罗列 debootstrap、QEMU、chroot，更重要的是解释为什么需要两阶段引导、为什么要挂载伪文件系统、为什么要保留 UID/GID。

### 14.3 遇到日志就全部归因于当前故障

例如 HDMI audio `-22`、Camera sensor 失败、PCIe link fail 可能与当前桌面无画面无关。要围绕故障路径区分相关错误和已知噪声。

### 14.4 夸大完成范围

当前可以写 Ubuntu rootfs、SDK 接入、桌面与 HDMI 排查；不能写全硬件稳定。诚实说明阶段边界通常比无法回答追问更专业。

### 14.5 没有量化数据却编造性能

性能数字必须能提供测试工具、素材、命令、日志和环境。没有数据时写“完成闭环验证”即可，不要虚构 FPS、功耗或提升比例。

## 15. 接下来如何把项目做得更适合求职

### 15.1 先关闭 P2

- 新镜像构建无 post-rootfs 错误；
- Xorg 配置自动进入镜像；
- 烧录后 LightDM/Xfce 自动启动；
- Wi-Fi/蓝牙文件完整；
- 保存最终日志、manifest 和 SHA256。

### 15.2 P3 优先完成 GPU 闭环

GPU 是很好的面试展开点，需要掌握：

- DRM/KMS 与渲染驱动区别；
- EGL/GBM/GLES；
- Mali kernel DDK 与 userspace DDK 配套；
- Xorg glamor 或 Wayland 合成；
- llvmpipe 与硬件 renderer 的区别。

### 15.3 做一个自动回归脚本

自动采集：

```text
os-release / uname / cmdline
systemctl --failed
DRM connector/state
EGL renderer
MPP/GStreamer plugins
Camera media graph
RKNPU version
dmesg error whitelist
```

对秋招而言，“我修过问题”很好，“我把问题变成自动化门禁”更能体现工程能力。

### 15.4 准备可展示证据

- Git 分支和清晰 commit；
- 系统架构图；
- 构建产物和 manifest；
- 一张 HDMI/Xfce 实机照片；
- 典型问题的日志前后对比；
- 最终测试表格。

注意去除密码、私钥、客户信息和无法公开的闭源二进制。

## 16. 自测题

如果下面问题不能脱稿回答，回到对应章节复习：

1. 为什么这是用户空间迁移，而不是更换整个 BSP？
2. U-Boot、kernel、DTB 和 rootfs 分别负责什么？
3. 为什么 x86_64 能在 chroot 中执行 arm64 的 dpkg？
4. `/dev` rbind 没卸载为什么会导致 `rm` 报 busy？
5. 为什么 `/dev/mali0` 存在仍不能证明 GPU 加速正常？
6. HDMI connected、EDID、CRTC active 分别证明什么？
7. 为什么 LightDM started 仍可能没有桌面？
8. `if ! cmd; then ret=$?` 为什么会吞掉错误码？
9. 为什么不能把整个 rootfs chown 给 UID 1000？
10. 如何证明一个视频使用了硬解码？
11. 如何区分 Ubuntu 引入的问题和 Debian 基线已有问题？
12. 当前项目哪些已经完成，哪些不能写进简历？

## 17. 推荐的复习主线

```text
Linux 启动流程
  -> U-Boot/FIT/bootargs
  -> kernel/DTB/driver model
  -> rootfs/init/systemd/udev
  -> debootstrap/chroot/QEMU
  -> module/firmware/ioctl/ABI
  -> DRM/KMS/Xorg/EGL
  -> MPP/RGA/GStreamer
  -> V4L2/media controller/RKAIQ
  -> RKNPU/IOMMU/DMA
  -> 构建系统/日志/测试/发布门禁
```

这条主线既对应本项目的实际推进顺序，也覆盖嵌入式 Linux/BSP 岗位常见面试知识。最重要的不是背诵定义，而是能把每个概念与自己遇到的真实日志、代码修改和验证结果对应起来。
