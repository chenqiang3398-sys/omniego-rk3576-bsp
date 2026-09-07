# T3 GStreamer-MPP 测试审查记录

## 1. 最终结论

结论：**PASS**。

当前收到的终端记录证明：

- `libgstrockchipmpp.so` 的动态库依赖均已解析；
- `librockchip_mpp.so.1`、`librga.so.2` 来自本次 SCP 测试目录；
- `gst-inspect-1.0 rockchipmpp` 返回 `0`；
- 成功注册 `mppvideodec`、`mppjpegdec`、`mpph264enc`、`mpph265enc` 等 6 个 element；
- 日志显示 `RGA enabled`。

实际 H.264 流水线也已通过：

- `h264_mpp_pipeline_exit_code=0`；
- 管线明确创建并运行了 `mppvideodec0`；
- 状态依次进入 `PAUSED`、`PREROLLED`、`PLAYING`；
- 收到 `Got EOS from element "pipeline0"` 并正常释放管线；
- 测试前后的 `dmesg` 增量为空，没有新增 MPP、RKVDEC、IOMMU、fault、reset、timeout 或 hang；
- `sha256sum -c` 对归档列出的 11 个日志文件全部校验通过；
- 结果包 SHA256：`51855832b36271dee16299c3fa430603b449681e2fc81279e223fd2c9cd82b33`。

CUDA、LADSPA、VA-API 扫描警告来自其他 GStreamer 插件，不是 Rockchip MPP 插件加载失败。

解码日志中的 `MPP is not able to generate pts` 和 `no matched frame` 与本次仅 1585 字节的短裸 H.264 elementary stream 缺少容器时间戳、帧匹配信息有关。管线仍正常到达 EOS、返回 0，内核也没有异常，因此不影响本次 smoke test 判定；后续固定素材兼容性测试应使用带正常时间戳的 MP4/MKV 文件继续覆盖。

## 2. 为什么 MPP 和 GStreamer 都要测

两次测试不是重复测试，而是分层验证：

```text
应用/播放器
    ↓
GStreamer pipeline 与 rockchipmpp 插件       ← 本次 GStreamer 测试
    ↓
Rockchip MPP 用户态库与 MPI API              ← 前一次 MPP 测试
    ↓
VPU/RKVDEC/RKVENC 内核驱动、IOMMU、硬件
```

MPP 的 `mpi_enc_test/mpi_dec_test` 直接调用厂家底层 API，用来证明编解码库、内核驱动和硬件本体可用。GStreamer 测试验证上层多媒体框架能发现插件、协商 caps、建立 pipeline，并通过 MPP 调用硬件。前者通过而后者失败时，问题通常位于插件版本、动态库、caps、parser 或 pipeline；两者都失败时才优先向 MPP/驱动/固件层排查。

## 3. 已归档证据

已归档 `T3-gstreamer-result.tar.gz`，其中包含：

- `h264-mpp-decode.txt`；
- `h264-mpp-result.txt`；
- `dmesg-before-h264.txt`、`dmesg-after-h264.txt`；
- `dmesg-h264-delta.txt`、`h264-mpp-kernel.txt`；
- 本次日志文件的 SHA256。

上述证据已经满足本阶段“流水线明确使用 `mppvideodec`、正常到达 EOS、退出码为 0、无新增内核异常”的验收要求。

## 4. 覆盖边界

本次证明了 GStreamer 到 Rockchip MPP 的 H.264 最小硬件解码闭环。尚未覆盖 H.265、JPEG、4K、容器解复用、音视频同步、长时间播放、CPU 占用和多路并发，这些属于后续兼容性及压力测试，而不是本次 smoke test 的阻塞项。
