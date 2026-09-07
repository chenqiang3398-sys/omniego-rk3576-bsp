# RK3576 官方 Debian P0 基线采集

## 1. 目标

官方 Debian 已经能够正常启动，说明当前 Loader、U-Boot、Linux 内核、DTB、分区布局和 rootfs 已形成可用基线。

在制作 Ubuntu 24.04 rootfs 前，应先采集 Debian Golden Reference，用于确认：

1. 厂家 Debian 下哪些硬件已经正常。
2. Ubuntu 移植后需要达到什么功能和性能水平。
3. 后续故障来自原始 BSP、板级 DTS，还是 Ubuntu 用户空间适配。

本文所有采集结果统一保存在：

```text
/home/linaro/rk3576-baseline/
```

最终压缩包为：

```text
/home/linaro/rk3576-debian-baseline.tar.gz
```

以下命令默认在开发板的 `linaro` 用户终端中执行。

## 2. 创建采集目录

```bash
BASELINE_DIR=/home/linaro/rk3576-baseline

mkdir -p "$BASELINE_DIR"
```

确认当前用户对目录具有写权限：

```bash
id
ls -ld /home/linaro "$BASELINE_DIR"
```

如果目录所有者不是 `linaro`，执行：

```bash
sudo chown -R linaro:linaro "$BASELINE_DIR"
```

## 3. 系统、板型和启动链信息

```bash
{
    date
    uname -a
    cat /etc/os-release
    cat /proc/cmdline
    printf 'Device tree model: '
    tr -d '\0' </proc/device-tree/model
    echo
    cat /proc/version
} | tee "$BASELINE_DIR/system-info.txt"

sudo dmesg -T > "$BASELINE_DIR/dmesg.txt"
journalctl -b --no-pager > "$BASELINE_DIR/journal.txt"
systemctl --failed --no-pager > "$BASELINE_DIR/systemd-failed.txt"

lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,PARTUUID,MOUNTPOINTS \
    > "$BASELINE_DIR/partitions.txt"
```

最关键的板型确认命令是：

```bash
tr -d '\0' </proc/device-tree/model
echo
```

输出必须与真实开发板一致。如果输出为 Rockchip EVB，但实际硬件是 OmniEgo、MLK-RK03 或其他自研板，应立即记录。系统能够开机不代表摄像头、触摸、SPI、电源、显示等板级配置完全正确。

## 4. 内核模块和设备节点

```bash
lsmod > "$BASELINE_DIR/lsmod.txt"

find /dev -maxdepth 2 \
    \( -name 'mali*' -o \
       -name 'video*' -o \
       -name 'media*' -o \
       -name 'rga*' -o \
       -name 'mpp*' -o \
       -name 'renderD*' -o \
       -name 'card*' \) \
    -ls > "$BASELINE_DIR/device-nodes.txt"

find /lib/modules -maxdepth 3 -type f \
    > "$BASELINE_DIR/kernel-modules.txt"

find /lib/firmware -maxdepth 4 -type f \
    > "$BASELINE_DIR/firmware.txt"
```

提取值得关注的内核日志：

```bash
sudo dmesg | grep -iE \
'panic|oops|fault|failed|error|timeout|reset|iommu|mali|gpu|rknpu|npu|mpp|rkvdec|rkvenc|rga|rkisp|csi|camera' \
    > "$BASELINE_DIR/kernel-important.txt" || true
```

不能仅凭日志出现 `error` 就判定硬件异常。设备树中启用但板上未安装的器件也可能产生无害报错，需要结合真实硬件判断。

## 5. GPU 和显示基线

检查测试工具是否存在：

```bash
{
    command -v eglinfo || true
    command -v glmark2-es2-wayland || true
    command -v glmark2-es2-drm || true
    command -v glmark2-es2 || true
    command -v modetest || true
} | tee "$BASELINE_DIR/gpu-tools.txt"
```

采集驱动和设备节点：

```bash
ls -l /dev/mali0 /dev/dri/* 2>/dev/null \
    | tee "$BASELINE_DIR/gpu-device-nodes.txt"

sudo dmesg | grep -iE 'mali|gpu|drm' \
    | tee "$BASELINE_DIR/gpu-dmesg.txt" || true
```

在图形桌面的终端中执行：

```bash
eglinfo 2>&1 | tee "$BASELINE_DIR/eglinfo.txt"
```

检查 `EGL vendor` 和 renderer。以下名称表示软件渲染，不能视为 GPU 正常：

```text
llvmpipe
softpipe
swrast
```

如果桌面运行 Wayland：

```bash
glmark2-es2-wayland 2>&1 \
    | tee "$BASELINE_DIR/glmark2-wayland.txt"
```

如果桌面运行 X11：

```bash
glmark2-es2 2>&1 \
    | tee "$BASELINE_DIR/glmark2-x11.txt"
```

保存相关软件包和动态库：

```bash
dpkg -l | grep -iE 'mali|mesa|egl|gles|drm|wayland|weston|xserver' \
    > "$BASELINE_DIR/gpu-packages.txt" || true

ldconfig -p | grep -iE 'mali|EGL|GLES|OpenCL' \
    > "$BASELINE_DIR/gpu-libraries.txt" || true
```

## 6. MPP、RGA 和硬编解码基线

```bash
dpkg -l | grep -iE 'mpp|rga|gstreamer|rockchip|v4l' \
    > "$BASELINE_DIR/multimedia-packages.txt" || true

gst-inspect-1.0 > "$BASELINE_DIR/gstreamer-all.txt" 2>&1

gst-inspect-1.0 | grep -iE 'mpp|rockchip|rga|v4l2' \
    | tee "$BASELINE_DIR/gstreamer-rockchip.txt" || true

sudo dmesg | grep -iE 'mpp|rkvdec|rkvenc|rga|iep|jpeg' \
    | tee "$BASELINE_DIR/mpp-rga-dmesg.txt" || true

find /usr /opt -type f \
    \( -iname '*mpi*dec*' -o \
       -iname '*mpi*enc*' -o \
       -iname '*mpp*test*' -o \
       -iname '*rga*test*' \) \
    2>/dev/null > "$BASELINE_DIR/mpp-rga-tools.txt"
```

建议将固定测试素材放到：

```text
/home/linaro/test-videos/
```

最低测试素材建议包含：

- H.264 1080p
- H.265 1080p
- H.265 4K
- AV1（产品要求时）
- JPEG

记录素材校验和：

```bash
mkdir -p /home/linaro/test-videos

find /home/linaro/test-videos -maxdepth 1 -type f -print0 \
    | sort -z \
    | xargs -0 -r sha256sum \
    > "$BASELINE_DIR/video-sha256.txt"
```

每项测试至少记录：

- 实际调用的软件插件或 MPP 工具
- 是否确认使用硬件解码
- 播放帧率和 CPU 使用率
- 内存占用
- 内核是否出现 MPP、IOMMU 或 reset 错误

仅仅“视频可以播放”不能证明硬解码正常，也可能使用了软件解码器。

## 7. 摄像头、ISP 和 RKAIQ 基线

确认摄像头驱动和 Sensor：

```bash
sudo dmesg | grep -iE \
'imx|ov[0-9]|gc[0-9]|camera|csi|cif|isp|rkaiq' \
    | tee "$BASELINE_DIR/camera-dmesg.txt" || true
```

记录所有 media graph：

```bash
for dev in /dev/media*; do
    [ -e "$dev" ] || continue
    name=$(basename "$dev")
    media-ctl -d "$dev" -p \
        > "$BASELINE_DIR/${name}.txt" 2>&1
done
```

记录所有 V4L2 节点：

```bash
v4l2-ctl --list-devices \
    > "$BASELINE_DIR/v4l2-devices.txt" 2>&1

for dev in /dev/video*; do
    [ -e "$dev" ] || continue
    name=$(basename "$dev")

    v4l2-ctl -d "$dev" --all \
        > "$BASELINE_DIR/${name}-all.txt" 2>&1

    v4l2-ctl -d "$dev" --list-formats-ext \
        > "$BASELINE_DIR/${name}-formats.txt" 2>&1
done
```

查找 IQ 文件：

```bash
find /etc /usr /oem /vendor -type f \
    \( -iname '*.xml' -o \
       -iname '*.json' -o \
       -iname '*iq*' \) \
    2>/dev/null > "$BASELINE_DIR/camera-iq-files.txt"
```

记录 Camera/RKAIQ 服务和进程：

```bash
systemctl list-units --type=service --all \
    | grep -iE 'rkaiq|camera|isp' \
    | tee "$BASELINE_DIR/camera-services.txt" || true

ps -ef | grep -iE 'rkaiq|camera|isp' \
    | grep -v grep \
    > "$BASELINE_DIR/camera-processes.txt" || true
```

摄像头基线至少需要明确：

- Sensor 和模组型号
- `/dev/media*` 与 `/dev/video*` 的对应关系
- 至少一个能够稳定采集的分辨率和帧率
- RKAIQ 服务是否运行
- 自动曝光、自动白平衡和自动对焦（如支持）是否生效
- IQ 文件路径和版本

## 8. NPU 基线

```bash
sudo dmesg | grep -iE 'rknpu|npu' \
    | tee "$BASELINE_DIR/npu-dmesg.txt" || true

find /usr /opt -type f \
    \( -iname 'librknnrt.so*' -o \
       -iname '*rknn*demo*' -o \
       -iname '*rknn*benchmark*' \) \
    2>/dev/null > "$BASELINE_DIR/npu-files.txt"

ldconfig -p | grep -i rknn \
    > "$BASELINE_DIR/npu-libraries.txt" || true

dpkg -l | grep -iE 'rknn|npu' \
    > "$BASELINE_DIR/npu-packages.txt" || true
```

如果厂家镜像包含 RKNN 示例，至少运行一个针对 RK3576 转换的模型，并记录：

- 原始模型和 RKNN 文件的 SHA256
- `librknnrt` 版本
- 推理输出结果
- 单次推理时间、P50/P95 或平均 FPS
- 连续运行是否稳定

建议将测试模型和结果分别放在：

```text
/home/linaro/rknn-models/
/home/linaro/rk3576-baseline/npu-results/
```

```bash
mkdir -p /home/linaro/rknn-models \
    "$BASELINE_DIR/npu-results"
```

## 9. 保存 Debian 软件包和厂家库清单

```bash
dpkg-query -W \
    -f='${Package}\t${Version}\t${Architecture}\n' \
    > "$BASELINE_DIR/packages.tsv"

dpkg -l > "$BASELINE_DIR/dpkg-list.txt"
ldconfig -p > "$BASELINE_DIR/ldconfig.txt"
```

记录关键厂家库的 SHA256：

```bash
find /usr/lib /lib -type f \
    \( -iname '*mali*' -o \
       -iname '*rknn*' -o \
       -iname '*rockchip*mpp*' -o \
       -iname '*rga*' -o \
       -iname '*rkaiq*' \) \
    -print0 2>/dev/null \
    | sort -z \
    | xargs -0 -r sha256sum \
    > "$BASELINE_DIR/vendor-libraries.sha256"
```

## 10. 打包采集结果

先确保结果归属于 `linaro` 用户：

```bash
sudo chown -R linaro:linaro "$BASELINE_DIR"
```

生成压缩包：

```bash
tar -C /home/linaro \
    -czf /home/linaro/rk3576-debian-baseline.tar.gz \
    rk3576-baseline
```

生成压缩包校验和：

```bash
sha256sum /home/linaro/rk3576-debian-baseline.tar.gz \
    | tee /home/linaro/rk3576-debian-baseline.tar.gz.sha256
```

检查结果：

```bash
ls -lh \
    /home/linaro/rk3576-debian-baseline.tar.gz \
    /home/linaro/rk3576-debian-baseline.tar.gz.sha256
```

## 11. P0 完成判据

进入 Ubuntu 专有组件移植前，应完成：

- 已确认 `/proc/device-tree/model` 与真实板型是否一致。
- 已保存完整 `dmesg`、journal、分区和软件包信息。
- 已确认 GPU renderer，不是 llvmpipe/softpipe/swrast。
- 已完成至少一个 MPP 硬件解码测试。
- 已确认摄像头 Sensor、media graph、IQ 文件及一个可采集模式。
- 已运行至少一个 RK3576 NPU 模型并保存结果。
- 已形成厂家 Debian 的已知问题清单。
- 已生成 `/home/linaro/rk3576-debian-baseline.tar.gz`。

P0 不要求厂家 Debian 中所有硬件都毫无错误，但必须明确每项能力当前是“正常、异常、未安装还是未测试”。厂家 Debian 中原本存在的 BSP/DTS 问题，不能在后续错误归因于 Ubuntu。

## 12. P0 后的 Ubuntu 第一个里程碑

P0 结束后，第一版 Ubuntu 暂不追求桌面和硬件加速，只实现：

- Ubuntu 24.04 arm64 用户空间
- systemd 正常启动
- eMMC rootfs 正常挂载
- 串口可以登录
- SSH 和有线网络正常
- `/lib/modules/$(uname -r)` 与当前 SDK 内核精确匹配
- firmware 正确安装
- 连续重启 10 次成功

第一版继续使用 Debian 已验证的同一套 Loader、U-Boot、boot.img、Linux 6.1、DTB 和 parameter/分区表，只替换 `rootfs.img`。之后再按 GPU、MPP/RGA、摄像头、NPU 的顺序迁移。
