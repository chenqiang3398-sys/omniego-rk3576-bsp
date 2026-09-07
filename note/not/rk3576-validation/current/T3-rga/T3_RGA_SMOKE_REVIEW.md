# T3 RGA 冒烟测试审查记录

## 1. 结论

结论：**PASS（带一项待固化的兼容性处理）**。

RGA2 Pro 能力查询成功，DMA-BUF 路径下的复制、缩放和颜色转换均完成，测试期间没有新增 RGA、DMA、IOMMU、fault、reset 或 timeout 内核错误。

## 2. 证据

- `query_exit_code=0`，识别到 `RGA_2_PRO` 和 librga API `v1.10.1_[10]`；
- copy：使用 DMA-BUF，耗时 `2341 us`；
- 1280×720 到 720×480 resize：使用 DMA-BUF，耗时 `2166 us`；
- RGBA8888 到 NV12：使用 DMA-BUF，耗时 `1705 us`；
- `dmesg-dmabuf-delta.txt` 为空，未发现新增内核异常；
- 三个 demo 的原始退出码均为 `1`。该版本示例程序以 `IM_STATUS_SUCCESS=1` 表示成功，不能按普通 shell 的“0 才成功”直接判失败，最终以操作完成日志、输出文件和内核日志联合判断。

原始证据包：`T3-rga-result.tar.gz`。

## 3. 已发现的兼容性问题

示例程序硬编码访问：

```text
/dev/dma_heap/system-uncached-dma32
```

当前厂家内核实际提供：

```text
/dev/dma_heap/system
/dev/dma_heap/system-uncached
/dev/dma_heap/reserved
```

测试时通过临时软链接把 `system-uncached-dma32` 映射到 `system-uncached`，成功进入 DMA-BUF 分配路径。该软链接已经在测试结束后删除，因此本次没有永久修改板端。

正式镜像不应依赖人工创建链接。后续应选择以下一种方式固化：

1. 优先修改/适配 demo 或调用方，按实际存在的 heap 名称选择；
2. 若闭源应用固定依赖旧名称，再由 udev/tmpfiles 规则提供兼容软链接。

## 4. 覆盖边界

本次属于最小功能冒烟测试，证明 RGA 查询、DMA-BUF 分配及基础 copy/resize/cvtcolor 链路可用；尚未覆盖多线程、长时间压力、更多像素格式、最大分辨率、并发 MPP/RGA 和结果图像逐像素正确性。
