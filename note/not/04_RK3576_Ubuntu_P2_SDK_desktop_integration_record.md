# RK3576 Ubuntu 24.04 P2 SDK 与桌面集成记录

## 1. 阶段目标

P2 将 P1 已启动成功的 Ubuntu 24.04 arm64 rootfs 纳入 Rockchip SDK 标准构建流程，并加入可启动的桌面基础环境。本阶段目标如下：

- 增加 `./build.sh ubuntu` 构建入口；
- 复用 SDK 的 kernel modules、post-rootfs、firmware 和 update.img 打包流程；
- 默认构建 Xfce + LightDM + X11 桌面；
- 输出包清单和镜像 SHA256，保证构建结果可追溯；
- 保持 P1 最小 rootfs 构建入口可复现。

P2 不宣称 GPU、视频硬解码、摄像头或 NPU 已可用。这些硬件用户态栈及实机稳定性属于 P3 及后续阶段。

## 2. 设计决策

### 2.1 桌面方案

采用 Xfce、LightDM 和 X11，原因是资源占用和依赖规模可控，同时与厂家 Debian 基线中的 X11 验证路径接近。默认 ext4 镜像由 P1 的 3072 MiB 增加到 5120 MiB，为桌面包及后续驱动用户态包预留空间。

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

### 2.3 chroot 清理

`ubuntu/scripts/common.sh` 统一管理 `proc`、`sys`、`dev` 挂载，并在构建退出时执行清理。这样处理是为了避免 P1 中断后出现 `rootfs/dev: Device or resource busy`，导致输出目录无法删除的问题。

## 3. 本阶段代码变更

- 新增 `device/rockchip/common/configs/Config.in.ubuntu`；
- 在 rootfs Kconfig 中增加 Ubuntu 选项；
- 在 `mk-rootfs.sh` 中增加 `build_ubuntu()`、命令帮助、清理和分发入口；
- 新增 `check-ubuntu.sh`，检查主机工具、binfmt、文件系统挂载属性和镜像源；
- 增加 base、desktop 两组软件包清单；
- 增加 Xfce、LightDM、NetworkManager 图形前端和 X11 基础工具；
- 让 SDK post-rootfs 识别 Ubuntu，并保持 `ID_LIKE=debian`；
- 保留 `build-minimal-rootfs.sh` 作为 P1 兼容包装器；
- 忽略临时构建目录 `ubuntu/binary/`，不把 rootfs 内容提交到 Git。

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
