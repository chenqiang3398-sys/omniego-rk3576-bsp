# RK3576 Ubuntu 24.04 P2 SDK 与桌面集成记录

## 1. 阶段目标

P2 将 P1 已启动成功的 Ubuntu 24.04 arm64 rootfs 纳入 Rockchip SDK 标准构建流程，并加入可启动的桌面基础环境。本阶段目标如下：

- 增加 `./build.sh ubuntu` 构建入口；
- 复用 SDK 的 kernel modules、post-rootfs、firmware 和 update.img 打包流程；
- 默认构建 Xfce + LightDM + X11 桌面；
- 输出包清单和镜像 SHA256，保证构建结果可追溯；
- 保持 P1 最小 rootfs 构建入口可复现。

P2 不宣称 GPU、视频硬解码、摄像头或 NPU 已可用。这些硬件用户态栈及实机稳定性属于 P3 及后续阶段。

### 1.1 先理解“桌面系统”是什么

这里的桌面不是一个单独软件，而是一组分层组件：

```text
LightDM（登录管理器）
        -> Xorg/X11（图形显示服务/协议）
        -> Xfce Session（桌面会话）
        -> xfwm4、xfdesktop、面板和桌面应用
```

- **X11** 是图形系统协议，规定应用如何创建窗口、绘制内容和接收键盘鼠标事件；Linux 上通常由 **Xorg** 实现 X11 server。
- **LightDM** 是 display manager，负责开机后启动 Xorg、显示登录界面、认证用户并启动桌面会话。
- **Xfce** 是桌面环境，包含窗口管理器、面板、文件管理器和设置中心；它不是内核，也不负责直接驱动 HDMI。

因此，LightDM 正常不代表 Xorg 一定正常，Xorg 正常也不代表 GPU 一定使用硬件加速。排查时要按“显示驱动 -> Xorg -> LightDM -> Xfce”分层判断。

## 2. 设计决策

### 2.1 桌面方案

采用 Xfce、LightDM 和 X11，原因是资源占用和依赖规模可控，同时与厂家 Debian 基线中的 X11 验证路径接近。默认 ext4 镜像由 P1 的 3072 MiB 增加到 5120 MiB，为桌面包及后续驱动用户态包预留空间。

启动时序是：systemd 进入 `graphical.target`，启动 LightDM；LightDM 拉起 Xorg，Xorg 打开 `/dev/dri/card*` 并完成 modeset；用户认证后 LightDM 启动 Xfce session，Xfce 再启动窗口管理器和桌面组件。X11 使用 C/S 模型：应用是 client，Xorg 是 server，输入事件由 server 分发给 client。

与 Wayland 的区别是：X11 由独立 X server 负责窗口和输入，兼容性好、调试工具多，但存在多 DRM 设备选卡和协议层开销；Wayland 由 compositor 直接管理显示，架构更现代，但板级驱动和桌面兼容性依赖更强。本阶段优先选择 X11 是为了复用 Debian 基线并降低首次移植变量。

面试要点：Xfce 是桌面环境，LightDM 是登录/会话管理器，X11 是显示协议，Xorg 是 X11 server；三者不能互相替代。

### 2.2 构建分层

Ubuntu 构建拆为三个稳定接口：

```text
ubuntu/mk-base-ubuntu.sh <target-dir> [release] [arch] [mirror]
ubuntu/mk-rootfs-noble.sh <target-dir>
ubuntu/mk-image.sh <rootfs-dir> <output-image> [size-mib] [manifest-dir]
```

SDK 中的 `build_ubuntu()` 只负责参数适配和生命周期编排。该接口的关键契约是最终必须生成：

```text
output/ubuntu/images/rootfs.ext4
output/firmware/rootfs.img
```

其中 `output/firmware/rootfs.img` 继续由 SDK 创建为相对符号链接，后续 `./build.sh firmware` 和 update.img 打包无需增加 Ubuntu 特例。

#### chroot、QEMU 与 rootfs 配置

`chroot` 是 `change root` 的缩写，作用是临时把某个目录当作进程看到的根目录 `/`。例如进入 `rootfs` 后，宿主机的 `rootfs/etc/os-release` 在 chroot 内显示为 `/etc/os-release`。它只改变文件系统视角，不创建独立内核，也不是虚拟机。

本项目开发机通常是 x86_64，而目标 Ubuntu rootfs 是 ARM64。为了在开发机中执行目标 rootfs 里的 ARM64 命令，SDK 配合 `qemu-aarch64-static` 使用：

```text
x86_64 开发机 + QEMU 用户态模拟 + chroot
    = 在开发机中配置 ARM64 Ubuntu rootfs
```

构建时 `configure-target.sh` 会在 chroot 内执行 `apt-get`、`locale-gen`、`useradd`、`systemctl enable` 等操作，因此这些配置会直接写入最终 Ubuntu 文件系统。

### 2.3 chroot 清理

`ubuntu/scripts/common.sh` 统一管理 `proc`、`sys`、`dev` 挂载，并在构建退出时执行清理。这样处理是为了避免 P1 中断后出现 `rootfs/dev: Device or resource busy`，导致输出目录无法删除的问题。

chroot 内的程序还需要访问几个虚拟文件系统：

```text
/proc  -> 进程、CPU 和内核状态
/sys   -> 设备、驱动和系统属性
/dev   -> 设备节点
```

因此构建脚本会临时把宿主机的这些文件系统挂载或绑定到 rootfs 下。退出 chroot 后必须递归卸载它们，再删除临时的 `qemu-aarch64-static`。脚本使用：

```bash
trap cleanup_chroot_filesystems EXIT
```

保证成功、失败或中断退出时都尝试清理。`Device or resource busy` 通常表示 `rootfs/dev`、`rootfs/proc` 或 `rootfs/sys` 仍是挂载点；Linux 不允许直接删除正在使用的挂载点，必须先卸载。chroot 与虚拟机的区别是：chroot 不运行独立内核、不隔离硬件，虚拟机则运行完整的客户机内核。

## 3. 本阶段代码变更

本节不仅记录“改了什么”，也说明每个文件在 SDK 中的职责，以及为什么要这样改。Rockchip SDK 将板卡配置、构建调度、rootfs 生成和镜像打包分层，便于 Debian、Ubuntu、Buildroot、Yocto 共用同一套入口。

### 3.1 `device/rockchip/common/configs/` 是什么

路径：

```text
device/rockchip/common/configs/
```

这是 Rockchip SDK 的公共配置目录，存放 Kconfig 输入文件。它不是某一块板子的设备树目录，而是定义“SDK 支持哪些构建能力以及这些能力如何配置”。例如：

```text
Config.in.kernel       # 内核配置
Config.in.loader       # U-Boot/SPL 配置
Config.in.rootfs       # rootfs 类型选择
Config.in.debian       # Debian 参数
Config.in.ubuntu       # Ubuntu 参数
Config.in.firmware     # 固件打包配置
Config.in.update       # update.img 配置
configs/post/          # rootfs 后处理钩子配置
```

新增 `Config.in.ubuntu` 的原因是让 Ubuntu 参数进入 SDK 的统一配置系统，而不是在 shell 脚本中写死。这样 `lunch`、defconfig、配置打印和构建脚本可以获得同一份配置来源。

### 3.2 rootfs Kconfig 是什么

文件：

```text
device/rockchip/common/configs/Config.in.rootfs
```

Kconfig 是 Linux 内核和 Rockchip SDK 使用的配置语言/配置系统。它通过 `config`、`choice`、`depends on`、`default` 等语句生成 `.config`，让用户选择 rootfs 类型和参数。

本工程中 `Config.in.rootfs` 引入：

```text
source "Config.in.ubuntu"
```

并定义：

```text
RK_ROOTFS_SYSTEM_BUILDROOT
RK_ROOTFS_SYSTEM_DEBIAN
RK_ROOTFS_SYSTEM_UBUNTU
RK_ROOTFS_SYSTEM_YOCTO
```

最终通过：

```text
RK_ROOTFS_SYSTEM=ubuntu
```

把配置选择传给 `mk-rootfs.sh`。因此，Kconfig 解决的是“构建什么 rootfs”的配置问题，`mk-rootfs.sh` 解决的是“如何构建这个 rootfs”的执行问题。

### 3.3 Ubuntu 配置文件

文件：

```text
device/rockchip/common/configs/Config.in.ubuntu
```

关键内容包括 Noble 版本、arm64 架构、镜像源、桌面 profile、镜像大小、主机名和默认用户等。这样做的好处是：配置可被 defconfig 保存、可在日志中复现，也能被 shell 构建脚本统一读取。

### 3.4 `mk-rootfs.sh` 与 `build_ubuntu()`

文件：

```text
device/rockchip/common/scripts/mk-rootfs.sh
```

这是 SDK rootfs 的统一调度脚本。它根据 `RK_ROOTFS_SYSTEM` 分发到不同实现：

```text
buildroot -> Buildroot 流程
debian    -> Debian 流程
ubuntu    -> build_ubuntu()
yocto     -> Yocto 流程
```

新增 `build_ubuntu()` 的目的，是把 Ubuntu 脚本适配到 Rockchip SDK 的 rootfs 契约中，负责传递输出目录、镜像大小、用户参数、内核模块目录，并继续调用统一的 post-rootfs、firmware 和 update.img 流程。这样不用复制一套新的 SDK 入口。

### 3.5 `check-ubuntu.sh`

文件：

```text
device/rockchip/common/scripts/check-ubuntu.sh
```

它在 debootstrap 前检查主机依赖、`qemu-aarch64-static`、binfmt、镜像源可达性和输出目录状态。提前失败的目的是把“主机环境问题”与“rootfs 配置问题”区分开，避免构建到一半才失败。

debootstrap 第一阶段
    |
    +-- 检查镜像源
    +-- 下载 ARM64 Ubuntu 包
    +-- 解包到 rootfs
    +-- 生成 /debootstrap 脚本
    |
    v
qemu-aarch64-static + chroot
    |
    +-- 执行 debootstrap second-stage
    +-- 完成 ARM64 基础系统配置

debootstrap 前置检查的目的是建立构建环境的前置条件。因为开发机是 x86_64，目标 rootfs 是 ARM64，所以需要检查 debootstrap、QEMU 和 binfmt；同时检查 Ubuntu ports 镜像源，避免下载阶段失败；检查输出目录，避免残留挂载和权限污染。这样可以把主机环境问题与 rootfs 配置问题分层隔离，使构建尽早失败并给出准确错误，而不是执行到后半段才出现难以定位的异常。

系统工具位置：
/usr/sbin/debootstrap

SDK 调用位置：
ubuntu/mk-base-ubuntu.sh

调用链：
./build.sh ubuntu
    -> mk-rootfs.sh
    -> build_ubuntu()
    -> mk-rootfs-noble.sh
    -> mk-base-ubuntu.sh
    -> /usr/sbin/debootstrap

### 3.6 软件包清单与桌面组件

文件：

```text
ubuntu/manifests/base.packages
ubuntu/manifests/desktop.packages
```

清单将基础系统和桌面系统分开：base 提供 systemd、SSH、网络等最小能力，desktop 追加 Xfce、LightDM、Xorg 和图形工具。这样可以通过 `minimal/desktop` profile 控制镜像规模，避免把桌面依赖强行带入最小系统。

### 3.7 post-rootfs、兼容字段与临时目录

让 post-rootfs 识别 Ubuntu，是为了继续复用 Wi-Fi/BT、hostname、locale、USB gadget 等厂家后处理逻辑；保留 `ID_LIKE=debian`，是因为大量 Debian 系工具和脚本通过该字段判断包管理生态。`build-minimal-rootfs.sh` 作为 P1 兼容包装器，保证旧的独立 rootfs 构建命令仍可用。`ubuntu/binary/` 是构建过程中的临时 rootfs，忽略它可以避免把数 GB 的生成文件提交到 Git，只保留脚本、清单和 overlay 等可复现输入。

## 4. 关键配置

```text
RK_UBUNTU_VERSION=noble
RK_UBUNTU_ARCH=arm64
RK_UBUNTU_PROFILE=desktop
RK_UBUNTU_IMAGE_SIZE_MB=5120
RK_ROOTFS_SYSTEM=ubuntu
```

开发阶段默认账号仍为 `linaro/linaro`，仅用于移植验证。生产镜像必须改为首次启动设置或安全注入方式，禁止保留默认口令。

## 5. 已完成验证

### 5.1 静态检查

- 所有新增及修改的 shell 脚本通过 `bash -n`；
- 新增脚本已设置可执行权限；
- Kconfig `olddefconfig` 可以生成 Ubuntu Noble/arm64/desktop 配置；
- `./build.sh ubuntu:dry-run` 成功，最终配置中 `RK_ROOTFS_SYSTEM=ubuntu`；
- dry-run 未执行 debootstrap、sudo 删除、镜像生成等有副作用步骤。

八股对应：`chroot` 只提供文件系统隔离，不能模拟 ARM CPU；本项目必须额外使用 `qemu-aarch64-static` 执行 ARM64 用户态程序。`proc`、`sys`、`dev` 是内核提供的虚拟文件系统，挂载是为了让 chroot 内的包管理、设备管理和模块工具看到必要的系统接口。

八股对应：构建系统将“生成 rootfs”和“编译内核”分离。rootfs 主要是 ARM64 软件包、chroot 和 QEMU 用户态模拟；内核、DTB 和 `.ko` 才通过 `ARCH=arm64` 与 `CROSS_COMPILE` 交叉编译。桌面包安装成功只证明用户态文件存在，不证明 DRM、GPU 或 Xorg 已经正确工作。

### 5.2 首次完整构建结果

2026-08-25 首次执行：

```bash
cd /home/magine/uisrc/mlk-sdk-3576-v1.1.0
./build.sh ubuntu
```

生成了以下产物：

```text
output/ubuntu/images/rootfs.ext4
output/ubuntu/manifests/packages.tsv
output/ubuntu/manifests/rootfs.ext4.sha256
output/firmware/rootfs.img -> ../ubuntu/images/rootfs.ext4
```

镜像大小为 5120 MiB，SHA256 为：

```text
4369573f25ccf0f1e8784bdc2b77c625e2c4535d6f78b8ee82a175f0e627b125
```

`sha256sum -c` 和 `e2fsck -fn` 均通过，且 `ubuntu/binary` 下没有遗留 `dev`、`proc`、`sys` 挂载。因此 debootstrap、桌面包安装和 ext4 镜像生成是成功的。

但是该次构建不能作为 P2 最终成功结果。post-rootfs 阶段存在明确错误：

```text
mkdir: cannot create directory 'ubuntu/binary/system': Permission denied
ERROR: 00-wifibt.sh - build_wifibt failed
```

`ubuntu/binary` 属于 `nobody:nogroup` 且目录权限为 `0755`，普通用户执行的厂家 Wi-Fi/蓝牙钩子无法创建 `/system`。更严重的是，内层钩子已返回失败，外层构建仍打印 `post-rootfs succeeded` 并继续生成镜像，导致仅依据命令退出状态和镜像存在性会产生误判。

该问题造成厂家 post-rootfs 生命周期未完整完成。结果镜像中没有安装 Debian 基线已有的 Rockchip Xorg 配置：

```text
/etc/X11/xorg.conf.d/20-modesetting.conf
```

### 5.3 HDMI 无画面排查过程

#### 5.3.1 初始现象

- Ubuntu 可以通过串口正常登录；
- systemd 到达 `graphical.target`；
- HDMI 连接显示器后没有 LightDM 登录画面；
- 初始启动日志中 U-Boot 曾输出 `hdmi@27da0000 disconnected`。

最初需要区分四类可能原因：HDMI HPD 未检测、EDID/DDC 读取失败、DRM 未完成 modeset、LightDM/Xorg 未启动。

#### 5.3.2 排除 HDMI 硬件链路

插入 HDMI 后，DRM sysfs 返回：

```text
/sys/class/drm/card0-HDMI-A-1/status: connected
```

显示器 EDID 可以解析出 `2560x1440`、`1920x1080`、`1280x720` 等模式。内核 DRM state 进一步确认：

```text
connector HDMI-A-1 -> video_port0
enable=1
active=1
mode=1920x1080@60
```

同时 HDMI PHY、DDC 和 Rockchip DRM 均已成功初始化。因此线缆、HPD、EDID、HDMI PHY、VOP2 和内核 modeset 不是无桌面的根因。启动日志中的 `route-hdmi: failed to get logo,offset` 只影响启动 Logo；HDMI audio codec 的 `-22` 属于独立音频问题，也不是此次视频无画面的原因。

#### 5.3.3 定位 LightDM/Xorg 失败

实际服务状态为：

```text
lightdm.service: failed (Result: exit-code)
Start request repeated too quickly
```

`/var/log/lightdm/x-0.log` 给出决定性错误：

```text
Fatal server error:
Cannot run in framebuffer mode. Please specify busIDs for all framebuffer devices
```

系统同时存在：

- `/dev/dri/card0`：Rockchip VOP2 显示 DRM；
- `/dev/dri/card1`：RKNPU 注册的 DRM/GEM 设备。

Ubuntu Xorg 自动探测时无法可靠选择显示 DRM，随后 X server 退出，LightDM 连续重试五次后失败。此前 `xrandr` 返回 `Can't open display :0` 是 Xorg 没有运行的结果，不是 Xauthority 本身的问题。

#### 5.3.4 板上验证修复

在板上增加 `/etc/X11/xorg.conf.d/20-modesetting.conf`，明确将 Rockchip DRM 设为主显示设备，并将 Xorg modesetting 驱动绑定到 `/dev/dri/card0`。P2 尚未移植 Mali 用户态栈，因此验证时使用软件渲染：

```text
Section "OutputClass"
    Identifier  "RockchipDRM"
    MatchDriver "rockchip"
    Option      "PrimaryGPU" "yes"
EndSection

Section "Device"
    Identifier  "Rockchip Graphics"
    Driver      "modesetting"
    Option      "kmsdev" "/dev/dri/card0"
    Option      "AccelMethod" "none"
EndSection

Section "Screen"
    Identifier  "Default Screen"
    Device      "Rockchip Graphics"
EndSection
```

清除 LightDM 失败状态并重新启动后，显示器成功出现桌面，验证通过。这证明 Xorg 多 DRM 设备选卡是此次 HDMI 无桌面的直接原因。

排查方法可概括为：先看 `/sys/class/drm/card*-*/status` 判断 HPD，再看 EDID 和 DRM state 判断 modeset，最后看 `systemctl status lightdm`、`/var/log/lightdm/x-0.log` 和 `ps -ef | grep Xorg` 判断桌面栈。`xrandr: Can't open display` 只能说明当前没有可连接的 X server，不能直接证明 HDMI 硬件损坏。

本案例中 `/dev/dri/card0` 是 Rockchip VOP2 显示设备，`card1` 是 RKNPU 注册的 DRM/GEM 设备。Xorg 自动选卡失败后报 `Cannot run in framebuffer mode`，所以通过 `PrimaryGPU=yes` 和 `kmsdev /dev/dri/card0` 固定显示主卡。`AccelMethod none` 只用于 P2 稳定性验证，表示暂不启用 GPU 2D 加速，不能作为 GPU 移植完成的证据。

### 5.4 本轮结论与重新编译要求

本轮完成了问题定位和板上修复验证，但手工创建的 Xorg 配置不在构建源码及原始镜像中，必须正式修复后重新编译。重新编译前需要同时完成：

1. 将 P2 使用的 Rockchip Xorg 主卡绑定配置纳入 Ubuntu rootfs 构建；
2. 修复 post-rootfs 对 root 所有目录的写入权限；
3. 让任一 post-rootfs 钩子失败能传递为 Ubuntu 构建失败，禁止带错误继续出镜像；
4. 确认 Wi-Fi/蓝牙脚本、固件和模块实际进入 rootfs；
5. 重新生成并校验 `rootfs.ext4`，再执行 HDMI、LightDM 和 Xfce 上板回归。

在以上源码修复和重新上板验收完成前，P2 状态保持为“修复验证通过，最终镜像待重编译”，不能进入 P3。

## 6. 上板验收项

1. 串口能够进入 systemd，且无 emergency mode；
2. LightDM 登录界面正常显示，`linaro` 能进入 Xfce；
3. `systemctl --failed` 无阻塞性服务失败；
4. `echo "$XDG_SESSION_TYPE"` 在桌面终端返回 `x11`；
5. 网络、SSH、键鼠、分辨率和重启关机正常；
6. 保存 `dmesg`、`journalctl -b`、`systemd-analyze` 和 `dpkg-query` 结果；
7. `glmark2` 或 `eglinfo` 此时可能落到 Mesa 软件渲染，不能据此判定 GPU 已迁移成功。

## 7. 下一阶段入口

完成 5.4 所列正式修复、重新编译和桌面回归后，才可关闭 P2 并进入 P3。P3 首先根据 Debian 基线逐项移植 Mali、RGA、MPP/GStreamer，再处理 Camera 和 RKNPU；每个子系统分别记录包来源、ABI、设备节点、运行测试和内核错误日志。
