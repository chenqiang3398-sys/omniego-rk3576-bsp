# RK3576 Ubuntu T3 MPP 编解码 Smoke Test 审查记录

## 1. 结论

**MPP H.264 硬件编码/解码最小闭环：PASS。**

本轮验证了 640x480、NV12、60 帧黑场素材的 H.264 编码和解码。本结论尚不覆盖 H.265、4K、10-bit、JPEG、多路并发、GStreamer 插件和长时稳定性。

## 2. 测试链路

```text
640x480 NV12 60 帧
    -> mpi_enc_test + librockchip_mpp
    -> RKVENC H.264
    -> 1585 字节 H.264 码流
    -> mpi_dec_test + librockchip_mpp
    -> RKVDEC H.264
    -> 640x480 NV12 60 帧
```

## 3. 关键证据

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 编码程序退出码 | PASS | `encoder_exit_code=0` |
| H.264 码流 | PASS | 1585 字节，`file` 识别为 JVT H.264 Level 4.0 |
| H.264 起始码/SPS | PASS | 头部包含 `00 00 00 01 67 ...` |
| 解码程序退出码 | PASS | `decoder_retry_exit_code=0` |
| 解码输出大小 | PASS | 27,648,000 字节 = 640 x 480 x 1.5 x 60 |
| 解码数据校验 | PASS | 解码输出 SHA256 与原始 NV12 输入一致 |
| 动态库选择 | PASS | `ldd` 加载 T3 临时目录中的 `librockchip_mpp.so.1` |
| 内核新增错误 | PASS | retry 前后 dmesg 无增量，无 IOMMU fault/reset/timeout/oops |

原始和解码输出的 SHA256 均为：

```text
f4c77051ab98f1ac6105bc3d3f284bbb9369ddaa6a64e8a333ebc1d1e2b9c76c
```

## 4. 首次解码失败与根因

首次执行：

```bash
mpi_dec_test -t h264 ... -v f
```

结果为：

```text
decoder_exit_code=255
decoded_size=0
```

失败期间 dmesg 没有新增 MPP/RKVDEC 消息，说明流程在用户态命令参数/初始化阶段已退出，不是硬件任务超时。当前使用的 Debian 厂家 demo 来自较旧的 MPP 1.5.0-1 包，改用文档明确定义的 H.264 数字类型后成功：

```bash
mpi_dec_test -t 7 -i output/nv12-640x480.h264 -n 60
```

因此根因归类为：**旧版 MPP demo 命令行参数兼容问题，非内核或 RKVDEC 硬件故障。**

`mpi_dec_test -help` 在该旧版二进制中返回 255 且无帮助文本，也属于 demo 行为，不作为 MPP runtime 失败依据。

## 5. 制品与留痕

```text
压缩包: T3-mpp-result.tar.gz
压缩包 SHA256:
cffc1cd016cbf39ee961c0a37a75b3638440201822390e7c97c920298929cd99
```

关键日志：

- `T3-mpp/logs/encoder-result.txt`
- `T3-mpp/logs/decoder-retry-result.txt`
- `T3-mpp/logs/decoded-retry-size.txt`
- `T3-mpp/logs/decoded-retry-sha256.txt`
- `T3-mpp/logs/dmesg-retry-delta.txt`
- `T3-mpp/logs/mpp-kernel-retry.txt`

## 6. 后续项

1. 继续 T3 RGA copy/resize/color-convert smoke test；
2. 准备固定的 H.264/H.265/JPEG 真实素材，扩展 MPP 格式矩阵；
3. 在 Ubuntu 24.04 sysroot 中重编当前 `external/mpp` 和 `gstreamer-rockchip`，不将这套旧 demo 参数行为带入正式发布包；
4. H.265、4K、多路和长时压力在后续阶段补齐。
