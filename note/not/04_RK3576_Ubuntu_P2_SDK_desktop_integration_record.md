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

### 5.2 待完成动态验证

完整构建需要联网下载 Ubuntu 软件包，并需要宿主机 sudo 权限。执行：

```bash
cd /home/magine/uisrc/mlk-sdk-3576-v1.1.0
./build.sh ubuntu
./build.sh firmware
```

构建完成后检查：

```bash
readlink -f output/firmware/rootfs.img
sha256sum output/ubuntu/images/rootfs.ext4
findmnt -R ubuntu/binary
```

`findmnt` 不应输出残留挂载。烧录时第一轮只替换 rootfs 分区，继续保留 P1 已验证的 Loader、U-Boot、boot.img、DTB 和 parameter。

## 6. 上板验收项

1. 串口能够进入 systemd，且无 emergency mode；
2. LightDM 登录界面正常显示，`linaro` 能进入 Xfce；
3. `systemctl --failed` 无阻塞性服务失败；
4. `echo "$XDG_SESSION_TYPE"` 在桌面终端返回 `x11`；
5. 网络、SSH、键鼠、分辨率和重启关机正常；
6. 保存 `dmesg`、`journalctl -b`、`systemd-analyze` 和 `dpkg-query` 结果；
7. `glmark2` 或 `eglinfo` 此时可能落到 Mesa 软件渲染，不能据此判定 GPU 已迁移成功。

## 7. 下一阶段入口

P2 完整构建和桌面上板验收通过后进入 P3。P3 首先根据 Debian 基线逐项移植 Mali、RGA、MPP/GStreamer，再处理 Camera 和 RKNPU；每个子系统分别记录包来源、ABI、设备节点、运行测试和内核错误日志。
