# 08 RK3576 GPU/Mali 用户态库排查与构建复盘

## 1. 本次目标

在 Ubuntu 24.04 桌面已经能够启动的基础上，验证 RK3576 GPU 是否使用硬件加速，并把厂家 Debian 中的 Mali 用户态库迁移到 Ubuntu rootfs。目标不是只让桌面显示，而是让 EGL/GLES/GBM 最终绑定 RK3576 的 Mali Bifrost G52。

## 2. 初始基线

桌面 X11 终端执行：

```bash
echo "$DISPLAY"
glxinfo -B
```

初始输出：

```text
direct rendering: Yes
OpenGL vendor string: Mesa
OpenGL renderer string: llvmpipe (LLVM)
Accelerated: no
```

`direct rendering: Yes` 只表示 X11 直接渲染接口可用，不等于 GPU 硬件加速。`llvmpipe` 是 Mesa 的 CPU 软件光栅化器，说明当前 OpenGL 由 CPU 执行。

## 3. 按层排查

### 3.1 DRM 设备层

板端执行：

```bash
ls -l /dev/dri
```

得到 `card0`、`card1`、`renderD128`、`renderD129`。其中 `card0` 对应 Rockchip VOP2 显示 DRM，`card1` 对应 RKNPU DRM；不能把 `card1` 当作 GPU 显示卡。

### 3.2 内核 Mali 驱动层

板端执行：

```bash
dmesg | grep -iE 'gpu|mali|panfrost|drm|iommu|reset'
```

关键日志：

```text
mali 27800000.gpu: Kernel DDK version g25p0-00eac0
mali 27800000.gpu: GPU identified as 0x2 arch 7.4.0
mali 27800000.gpu: Probed as mali0
Mali device driver loaded
```

结论：设备树 GPU 节点、时钟/电源基础链路和 Mali 内核驱动 probe 已成功。当前不需要重新编译内核，问题转移到用户态 EGL/GLES/GBM 库选择。

### 3.3 用户态库层

板端执行：

```bash
ldconfig -p | grep -Ei 'mali|EGL|GLES|gbm'
```

初始只有 `libEGL_mesa.so`、Mesa `libGLESv2.so` 和 `libgbm.so`，所以 `glxinfo` 使用 `llvmpipe`。

## 4. SDK 中确认正确 Mali 包

SDK 源码终端执行：

```bash
cd /home/magine/uisrc/mlk-sdk-3576-v1.1.0
grep -nE 'rk3576|bifrost-g52|valhall-g610' external/libmali/gpu-chips.txt
```

工程映射为：

```text
bifrost-g52: rk3566_rk3568 rk3562 rk3576
valhall-g610: rk3588
```

因此 RK3576 应使用：

```text
libmali-bifrost-g52-g24p0-x11-wayland-gbm_1.9-1_arm64.deb
```

不能使用 RK3588 的 Valhall G610 包。SDK 中虽然同时保存多套 Mali 包，但它们面向不同 GPU 架构，不能混装。

## 5. `.deb` 包内容验证

SDK 源码终端执行：

```bash
dpkg-deb -f debian/binary/libmali-bifrost-g52-g24p0-x11-wayland-gbm_1.9-1_arm64.deb Package Version Architecture Depends
```

确认架构为 `arm64`。查看包内容：

```bash
dpkg-deb -c debian/binary/libmali-bifrost-g52-g24p0-x11-wayland-gbm_1.9-1_arm64.deb \
| grep -E 'libmali|libEGL|libGLES|libgbm|OpenCL|firmware|ld.so'
```

该 Bifrost 包包含：

```text
libmali.so.1.9.0
mali/libEGL.so.1
mali/libGLESv1_CM.so.1
mali/libGLESv2.so.2
mali/libMaliOpenCL.so.1
mali/libgbm.so.1
etc/ld.so.conf.d/00-aarch64-mali.conf
```

它不包含 `mali_csffw.bin`。该文件只出现在 Valhall G610 包中，不能跨 GPU 架构复制。因此“Bifrost 包缺少 mali_csffw.bin”不是当前故障证据，不能拿 Valhall 固件替代。

## 6. 手动 chroot 测试过程

### 6.1 为什么必须进入 chroot

在宿主机直接执行 `dpkg -i` 操作的是开发机的 `/var/lib/dpkg`，会出现权限错误或污染宿主环境。目标 ARM64 rootfs 必须通过 chroot 使用自己的 dpkg 数据库。

SDK 源码终端：

```bash
mkdir -p ubuntu/binary/tmp/ubuntu-packages
cp debian/binary/libmali-bifrost-g52-g24p0-x11-wayland-gbm_1.9-1_arm64.deb \
    ubuntu/binary/tmp/ubuntu-packages/
sudo chroot ubuntu/binary /bin/bash
```

进入后提示符变为 `root@...:/#`，此时才是在目标 Ubuntu rootfs 中执行：

```bash
dpkg -i /tmp/ubuntu-packages/libmali-bifrost-g52-g24p0-x11-wayland-gbm_1.9-1_arm64.deb
```

第一次安装提示：

```text
Package libxcb-dri2-0 is not installed
```

这说明 Mali 包已解包，但 X11 依赖未满足。直接执行 `apt-get install -f` 可能会删除未配置的 Mali 包，因此正确顺序是先安装依赖，再安装 Mali 包。

### 6.2 chroot 挂载知识

手动 chroot 可能出现：

```text
Can not write log (Is /dev/pts mounted?)
```

因为 `/dev/pts` 未挂载。正式 SDK 脚本通过 `ubuntu/scripts/common.sh` 统一挂载 `/proc`、`/sys`、`/dev`，并用 `trap cleanup_chroot_filesystems EXIT` 在退出时卸载。不能把宿主机的 `proc/dev/sys` 目录递归复制进 Git 或 rootfs。

## 7. 正式自动化修改

### 7.1 本地包输入

Mali 包放入：

```text
ubuntu/packages/arm64/
```

`ubuntu/mk-rootfs-noble.sh` 将本地 `.deb` 复制到：

```text
rootfs/tmp/ubuntu-packages/
```

### 7.2 依赖和安装顺序

`ubuntu/manifests/desktop.packages` 增加：

```text
libxcb-dri2-0
```

`ubuntu/configure-target.sh` 在 chroot 中先安装 manifest 软件包，再执行：

```text
dpkg -i /tmp/ubuntu-packages/libmali-*.deb
ldconfig
```

这样每次完整构建都能复现 Mali 用户态库、动态库搜索路径和包状态，不依赖人工进入 chroot。

## 8. 为什么这一步不需要编译内核

内核日志已经出现：

```text
Probed as mali0
Mali device driver loaded
```

说明内核驱动和设备树基础链路通过。本阶段改动的是：

```text
libmali.so
libEGL.so
libGLESv2.so
libgbm.so
ld.so.conf.d
OpenCL/Vulkan 用户态配置
```

所以只需要重新构建 Ubuntu rootfs 并烧录 `rootfs.ext4`。只有 GPU probe 失败、DTS 节点关闭、IOMMU fault、reset 失败或内核驱动源码变化时，才需要 `./build.sh kernel`。

## 9. 构建与板端验证

SDK 源码终端：

```bash
./build.sh ubuntu
grep -E 'libmali|libxcb-dri2' output/ubuntu/manifests/packages.tsv
```

板端桌面终端：

```bash
ldconfig -p | grep -Ei 'mali|EGL|GLES|gbm'
glxinfo -B
eglinfo
glmark2-es2
```

成功目标：

```text
OpenGL renderer 不再是 llvmpipe
Accelerated 不再是 no
EGL/GLES 库来自 Mali/Bifrost
glmark2 能运行且无 GPU reset/IOMMU fault
```

同时必须保留：

```text
/etc/X11/xorg.conf.d/20-modesetting.conf
PrimaryGPU=yes
kmsdev /dev/dri/card0
```

先保持 HDMI 显示稳定，再单独验证 GPU；不要同时删除 Xorg card0 绑定和修改加速方式。

## 10. 秋招八股

- **内核态与用户态**：Mali 内核驱动负责设备 probe、内存映射、IOMMU 和提交任务；`libmali` 负责 EGL/GLES/GBM API 和用户态命令提交；两者必须 ABI/版本匹配。
- **DRM 与 render node**：`card*` 主要承载显示控制，`renderD*` 用于非特权渲染。存在 DRM 节点不等于已经启用硬件渲染。
- **EGL/GLES/GBM**：EGL 创建上下文和 surface，GLES 提供 OpenGL ES API，GBM 分配可被 DRM/KMS 使用的 buffer；Xorg/Wayland 通常通过它们连接用户态 GPU 和显示系统。
- **llvmpipe**：Mesa 的软件光栅化器，使用 CPU 执行 OpenGL；看到它说明 API 可用，但 GPU 硬件加速未生效。
- **动态库搜索**：`ldconfig` 根据 `/etc/ld.so.conf.d/*.conf` 建立缓存；Mali 包将 `/usr/lib/aarch64-linux-gnu/mali` 加入搜索路径，但最终是否选中 Mali 仍需用 `glxinfo/eglinfo` 验证。
- **依赖解析**：`dpkg -i` 只负责安装本地包，不自动解决依赖；`apt` 负责依赖解析。未配置的本地包直接执行 `apt-get -f` 可能被删除，因此构建脚本应先装依赖再装本地包。
- **分层排查**：GPU 问题应按“设备树/内核 probe -> DRM 节点 -> 用户态库 -> EGL 初始化 -> Xorg/Wayland -> 应用性能”顺序定位。

面试项目表述：

> 在 RK3576 Ubuntu 24.04 移植中，我先用 `glxinfo` 定位到 `llvmpipe`，再通过 DRM 节点和 dmesg 证明 Mali 内核驱动已 probe 成功，最终确认缺少的是 Bifrost G52 用户态 EGL/GLES/GBM 库。通过识别 RK3576 与 Bifrost G52 的芯片映射、校验 ARM64 `.deb` 内容、在 chroot 中处理依赖，并将本地包接入 rootfs 自动化构建，建立了从内核驱动到桌面 OpenGL 的完整验证链路。
