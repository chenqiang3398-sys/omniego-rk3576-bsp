# RK3576 Debian P0 基线评审

## 结论

当前基线可以进入 Ubuntu 24.04 最小 rootfs 阶段。P1 只替换 rootfs，继续复用官方镜像已经验证的 Loader、U-Boot、boot.img、Linux 6.1.99、DTB 和分区表。

## 已确认基线

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| 系统 | Debian 12 bookworm arm64 | `system-info.txt` |
| 内核 | Rockchip BSP Linux 6.1.99 | `system-info.txt` |
| 板型 DTB | Rockchip RK3576 EVB1 V10 Board | `system-info.txt` |
| rootfs | eMMC `mmcblk0p6`，ext4，14 GiB | `partitions.txt` |
| systemd | 无 failed unit | `systemd-failed.txt` |
| GPU | ARM Mali-G52，Bifrost g24p0，OpenGL ES 3.2 | `eglinfo.txt`、`glmark2-x11.txt` |
| 多媒体插件 | MPP H.264/H.265 编码、MPP 视频/JPEG 解码可发现 | `gstreamer-rockchip.txt` |
| MPP 工具 | `mpi_dec_test`、`mpi_enc_test` 等已安装 | `mpp-rga-tools.txt` |
| 测试素材 | H.264/H.265/AV1/JPEG 已保存 SHA256 | `video-sha256.txt` |
| NPU runtime | `/usr/lib/librknnrt.so` 存在 | `npu-files.txt` |
| Camera 框架 | CSI/CIF/ISP/VPSS 驱动和节点存在 | `camera-info/` |

## 尚未完成或不能判定通过

1. `glmark2-x11.txt` 只记录到第一个场景，未包含最终 Score，因此 GPU 初始化通过但完整性能基线未完成。
2. 没有保存 MPP 对测试视频的实际解码结果、帧率、CPU 和内核日志，当前只能确认插件和工具存在。
3. NPU 只确认 runtime 存在，没有 RK3576 模型推理结果，不能判定 NPU 用户态链路通过。
4. IMX415 probe 读取到 `sensor id 000000`，Camera sensor 链路不通过；RKAIQ 服务处于 inactive。

这些项目不阻塞 P1 最小 Ubuntu 启动，但在进入对应的 GPU、MPP、Camera、NPU 迁移阶段前必须补齐。

## BSP 已知问题

- 当前运行 DTB 自报为 `Rockchip RK3576 EVB1 V10 Board`。若量产硬件不是 EVB1，必须在硬件加速适配前冻结真实板型和 DTB。
- IMX415 缺少 power GPIO/regulator 配置并且 I2C ID 读取失败。
- Goodix 触摸 I2C probe 失败。
- RKVENC 两个核心的 OPP/devfreq 初始化失败，需要在视频编码验收时评估性能与温控影响。
- 部分 SPI/I2C pin 存在占用冲突。
- `regulatory.db` 缺失。

上述问题来自厂家 Debian/BSP 基线，不应在 Ubuntu 阶段被误判为 Ubuntu 回归。

## P1 验收目标

- Ubuntu 24.04 arm64 systemd 启动到串口登录。
- rootfs 从原 `PARTUUID=614e0000-0000` 对应分区挂载。
- hostname、用户、SSH 和有线网络正常。
- 内核模块目录与 `uname -r` 精确匹配。
- Rockchip/Wi-Fi 固件已安装。
- 不安装或启用 Mali、MPP、RKAIQ、RKNPU2 用户态组件。
- 连续重启 10 次成功。

