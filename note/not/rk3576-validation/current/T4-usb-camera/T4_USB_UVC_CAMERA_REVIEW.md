# T4 USB UVC 摄像头测试审查记录

## 1. 结论

结论：**PASS（USB UVC 采集及 MPP 编解码组合链路）**。

本次证明了以下链路可用：

```text
Realtek USB Camera 0bda:5844
    -> USB/UVC 内核驱动
    -> /dev/video73 V4L2 capture
    -> GStreamer v4l2src
    -> 1280x720@30fps MJPEG 连续采集
```

`/dev/video74` 不具备 capture capability，不作为图像采集节点。

## 2. 关键证据

- `udevadm` 确认 `/dev/video73` 的 `ID_V4L_CAPABILITIES=:capture:`；
- `/dev/video74` 没有 capture capability，探测返回 255 符合节点类型；
- `gst-inspect-1.0 v4l2src` 返回 0；
- 自动协商格式为 `image/jpeg, 1280x720, 30/1, progressive`；
- 30 帧探测正常到达 EOS；
- 300 帧测试在 `10.248065590 s` 内完成，接近 30 fps，退出码为 0；
- 隔离测试确认 `mppjpegdec` 输出 30 个 NV16 buffer；
- 隔离测试确认 `mpph264enc` 输出 60 个 H.264 buffer，文件大小 788 KiB；
- 首次组合测试生成 0 字节文件，定位为 JPEG 解码输出 NV16、编码器要求 NV12，中间缺少格式转换；
- 加入 `videoconvert` 完成 NV16 到 NV12 转换后，组合管线输出 300 个编码 buffer；
- 最终 H.264 文件大小 4.1 MiB，SHA256 为 `440cdee8afd9b7504977a422bc6912d8a2f69f3b5987e5b1efe95cb7037a2375`；
- 最终文件经 `h264parse ! mppvideodec ! fakesink` 硬解码复验，正常到达 EOS、退出码为 0；
- 没有新增 UVC/USB reset、disconnect、stall、buffer overflow 或 timeout；
- 归档列出的 18 个日志文件均通过 SHA256 校验；
- 结果包 SHA256：`b2a8c959b3659e9614a54c08d6fa7973618fb2511e85457b4850aede31e7163b`。

## 3. 日志边界说明

`dmesg` 增量中的 RKCIF `update sensor info failed -19` 来自厂家 DTS 已启用、但当前未连接传感器的 MIPI/RKCIF 节点。AIC 日志记录的是并行发生的 Wi-Fi 漫游。二者均不属于 `/dev/video73` 的 UVC 采集错误，不影响本项结论。

## 4. 已验证的组合链路

```text
/dev/video73 MJPEG 1280x720@30fps
    -> jpegparse
    -> mppjpegdec（硬件 JPEG 解码，输出 NV16）
    -> videoconvert（NV16 转 NV12）
    -> mpph264enc（硬件 H.264 编码）
    -> H.264 文件
    -> mppvideodec（硬件解码复验）
```

## 5. 尚未覆盖

- 实际画面内容和单帧文件有效性；
- USB 摄像头长时间运行和热插拔恢复；
- 用 RGA 替代当前 CPU `videoconvert` 的零拷贝/硬件格式转换优化；
- 多路摄像头并发和长时间编解码压力；
- MIPI CSI、传感器驱动、RKCIF、RKISP、RKAIQ 和 3A（因无 MIPI 模组暂缓）。
