# RK3576 Ubuntu T2 NPU Smoke Test 审查结论

## 1. 结论

**T2 NPU 最小推理闭环：PASS（smoke test）。**

本结论只表示“RK3576 模型 + RKNN runtime + RKNPU 内核驱动”已完成一次有效推理，不代表已完成长时压力、多 context、zero-copy、业务模型精度或性能封版。

## 2. 已验证项

| 检查项 | 结果 | 证据 |
| --- | --- | --- |
| 目标系统 | PASS | Ubuntu 24.04 LTS arm64，Linux 6.1.99 |
| 普通用户权限 | PASS | `linaro` 属于 `video` 和 `render` 组 |
| NPU DRM 设备 | PASS | `/dev/dri/card1`、`renderD128`、`renderD129` 存在 |
| 用户态库加载 | PASS | `ldd` 确认加载测试目录中的 `librknnrt.so` |
| 动态依赖 | PASS | `ldd` 无 `not found` |
| runtime/driver 握手 | PASS | RKNN runtime 2.3.0，RKNPU driver 0.9.8 |
| RK3576 模型加载 | PASS | `mobilenet_v1.rknn` 输入/输出 tensor 解析成功 |
| 单次推理 | PASS | 5.83 ms，171.41 FPS |
| 分类输出 | PASS | 输出 Top-5 结果，Top-1 index=156，score=0.935059 |
| NPU 致命内核错误 | PASS | 未见 NPU IOMMU fault、job timeout、NPU reset、oops 或 panic |

## 3. 关键版本和性能记录

```text
rknn_api/rknnrt: 2.3.0
runtime commit: c949ad889d
runtime build time: 2024-11-07 11:35:33
RKNPU driver: 0.9.8
model: RK3576/mobilenet_v1.rknn
input: dog_224x224.jpg
latency: 5.83 ms
reported FPS: 171.41
Top-1: index 156, score 0.935059
```

## 4. 日志中需要分开处理的告警

以下信息在启动阶段已经存在，本次推理仍然成功，因此不判定为 T2 NPU 失败：

- RKNPU `can't request region for resource` 后仍成功 `Initialized rknpu 0.9.8`；
- RKNPU debugfs 目录重复创建告警；
- Goodix 触摸 I2C `-6` 错误；
- Camera sensor/CIF remote endpoint 错误；
- HDMI audio ASoC `-22` 错误；
- regulatory.db 缺失；
- VPSS/RKVDEC reset resource 提示。

这些告警应在后续 Camera、音频、Wi-Fi 合规数据库和 DTS 基线检查中分别归档，不应与 NPU 用户态问题混合。

## 5. 本次证据的限制

- 压缩包未包含单独的程序退出码文件，但推理输出完整；
- `dmesg-before.txt` 和 `dmesg-after.txt` 是开机后的累计日志，没有使用 `dmesg -C` 或时间窗口隔离本次推理新增消息；
- 尚未执行循环压力、多 context并发、DVFS/温度和内存稳定性测试；
- 尚未与厂家 Debian Golden Reference 的同模型性能比较。

## 6. 阶段判定

T2 的“最小推理闭环”已完成，可进入 T3 MPP/RGA/硬解码测试。NPU 的长时压力、多 context和业务模型归入 T8 并发与稳定性阶段。
