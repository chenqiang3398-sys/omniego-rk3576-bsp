# OmniEgo RK3576 底板 BSP 移植与裁剪方案

## 1. 总体判断

当前硬件是“米联客 MLK-CR03 RK3576 核心模块 + 自研底板”。因此不应从零寻找所谓“核心板 SDK”，也不应直接把官方开发板 DTS 大量删改成新板。

推荐策略：

1. 继续复用官方开发板 SDK 中与核心模块绑定的启动链、DDR、PMIC、eMMC 和 RK3576 SoC 公共代码。
2. 新建自研底板 DTS，继承最接近的核心板/开发板 `.dtsi`。
3. 只在新 DTS 中描述底板差异；先通过 `status = "disabled"` 关闭不存在的官方外设。
4. 硬件全部稳定后，再裁剪内核配置、模块、Buildroot/Ubuntu 软件包和镜像分区。

最重要的原则是：**先移植、后验证、最后裁剪**。不要一开始同时改 DTS、驱动、内核配置和根文件系统，否则出现问题时无法区分是硬件描述错误、驱动缺失还是功能被裁掉。

## 2. 核心板与底板的软件边界

### 2.1 应优先保留的核心板部分

- RK3576 BootROM、MiniLoader/TPL/SPL 相关配置。
- DDR 初始化二进制和内存参数。
- RK806/核心板 PMIC、核心电压与 DVFS 配置。
- eMMC、时钟、复位、GRF、IOMMU、thermal、watchdog。
- RK3576 公共 `.dtsi`、CPU OPP、GPU/NPU/VPU/RGA/ISP 等 SoC 节点。
- USB OTG 烧写/救砖链路和 UART0 调试串口。

这些内容主要由核心模块决定。自研底板不应在第一阶段修改 DDR、PMIC、OPP 或 Loader。

### 2.2 需要为自研底板重新描述的部分

- 底板电源和外设使能 GPIO。
- 4 路 MIPI CSI 端口及完整 media graph。
- 相机 I2C、PWDN、MCLK、lane 数和硬件触发。
- Type-C 控制器及 USB role-switch。
- USB Hub 和 USB Wi-Fi。
- MIPI DSI LCD、触摸、背光和复位。
- HDMI、TF 卡、RTC、音频、风扇、按键、LED、传感器接口和电池充电管理。

## 3. 从原理图得到的外设矩阵

| 模块 | 实际硬件连接 | Linux 子系统/建议驱动 | 设备树重点 | 结论 |
|---|---|---|---|---|
| 调试串口 | `UART0_TX/RX_M0_DEBUG` | 8250/DW UART | console、pinctrl | 必须最先保留 |
| 风扇 | `PWM2_CH5_M1_FAN` 驱动三极管/MOS 管 | `pwm-fan` | PWM 极性、周期、cooling-levels | 无需自写驱动 |
| Type-C | USB2/USB3 OTG、CC1/CC2、I2C2、`USBCC_INT_L` | 控制器很像 FUSB302，需以 BOM/丝印确认；`fusb302` + TCPM | I2C 地址、中断、connector、role-switch、VBUS regulator | 不能只启用 USB PHY |
| USB 供电 | `SY6280AAC` 负载开关 | regulator-fixed / gpio-regulator（视使能方式） | `USB_OTG0_PWREN_H`、`USB_HOST1_PWREN_H` | 需要和 USB 控制器供电关联 |
| USB Hub | `CH334F` | 内核通用 USB Hub | 通常无需 DTS 子节点 | 应保留 USB Hub 支持 |
| Wi-Fi | `SKI.WB800D80U.2`，经 CH334F 接 USB2 Host1 | USB Wi-Fi 驱动由 VID:PID 决定 | 一般不建 SDIO Wi-Fi 节点 | 删除官方 SDIO Wi-Fi 前先用 `lsusb -nn` 确认芯片 |
| HDMI 2.1 | RK3576 原生 HDMI TX | Rockchip DRM/DW HDMI | HDMI、PHY、HPD、5 V/enable | 通常不需要板级新驱动 |
| LCD | **单 lane MIPI DSI**，2.8 V/3.3 V，独立 reset；触摸走 I2C0 | DRM panel + DSI host；触摸驱动按触控 IC | lane=1、mode、init sequence、reset、背光、触摸 IRQ | 必须取得屏型号和初始化命令 |
| Audio Codec | 原理图标注 `ES838`，管脚与 ES8388 类似；SAI1 + I2C3 | ES8388 codec + ASoC machine card | MCLK、format、主从关系、routing、HP detect | 型号必须由 BOM 再确认 |
| 功放 | 两路 PAM8303 类模拟功放，`SPK_CTL_H` | `gpio-hog`、codec GPIO 或简单放大器组件 | shutdown GPIO | 不建议单独写复杂驱动 |
| TF 卡 | `SDMMC0_D0~D3/CMD/CLK`、`DET_L`、`PWREN_H` | `dw_mmc-rockchip` | bus-width=4、cd-gpios、vqmmc/vmmc、pinctrl | 可参考官方开发板 TF 节点 |
| RTC | I2C2、`RTC_INT`、32 kHz 输出，经 TXS0102 | RTC 驱动取决于 U701 型号 | 地址、IRQ、wakeup-source、clock output | PDF 中料号重叠，必须查 BOM |
| 按键 | `SARADC_VIN0_BOOT`、`SARADC_VIN1_KEY` | `adc-keys` | 各键电压阈值、keyup-threshold | 无需自写驱动 |
| LED | 与 PWM/GPIO 复用网络有关 | `gpio-leds` 或 `pwm-leds` | 核实与相机触发的复用冲突 | 相机触发启用后不能继续当普通 LED |
| 传感器接口 | I2C2 和 I2C7 扩展口 | 具体 sensor 驱动 | 地址、IRQ、供电、pinctrl | 接口本身无需驱动 |
| 电池充电 | U901 为 24-pin I2C charger，管脚特征接近 BQ2589x；I2C7，`BATCH_INT/OTG/nCE` | 若确认 BQ25895，可用 `bq25890_charger`；否则适配 power_supply 驱动 | IRQ、OTG、charge-enable、VBUS/BAT supplies | 必须先确认 U901 精确型号 |
| 电源轨 | SYS_VBAT 产生 5 V、3.3 V、1.8 V、2.8 V | 多数为 always-on/fixed supply | 必要时建立 fixed-regulator 供消费者引用 | 不要误写成 PMIC 动态电源 |

## 4. 四路相机是本项目的最大风险点

### 4.1 原理图映射

| 连接器 | PHY/数据线 | 控制总线 | 控制信号 | 触发 |
|---|---|---|---|---|
| CAM0 / CN301 | CSI0 CLK + D0/D1，2-lane | I2C4 M3 | `MIPI_CAM0_PDN_L` | `CSI_TRIGGER1` |
| CAM1 / CN302 | CSI1 CLK + D0~D3，可接 4-lane | I2C5 M1 | `MIPI_CAM1_PDN_L` | `CSI_TRIGGER2` |
| CAM2 / CN303 | CSI2 CLK；数据复用 CSI1 D2/D3 为 CSI2 D0/D1 | I2C8 M1 | `MIPI_CAM2_PDN_L` | `CSI_TRIGGER3` |
| CAM3 / CN304 | CSI3 CLK + D0/D1，2-lane | I2C9 M1 | 图中接 `Gyroscope_INT`，需确认是否缺少独立 PWDN | `CSI_TRIGGER4` |

### 4.2 关键限制

CAM1 的 D2/D3 与 CAM2 的 D0/D1 是同一组复用物理通道。四路同时工作时，不能把 CAM1 配成 4-lane 后再同时启用 CAM2。合理方案通常是：

- CAM0：2-lane；
- CAM1：2-lane，只用 CSI1 D0/D1；
- CAM2：2-lane，使用 CSI2 对 CSI1 D2/D3 的 split 映射；
- CAM3：2-lane。

必须在 RK3576 SDK 的参考 DTS 中找到 CSI1/CSI2 split 或 multi-channel 的官方示例，照着节点名称和 graph 拓扑修改，不能凭 SoC 通用名称猜节点。

### 4.3 相机驱动分层

1. **传感器驱动**：I2C probe、寄存器表、曝光/增益、帧率、V4L2 controls、stream on/off。
2. **板级 DTS**：I2C 地址、MCLK、PWDN/reset、regulators、lane 数、endpoint、remote-endpoint。
3. **RK3576 media graph**：sensor -> DPHY -> CSI2 host -> RKCIF -> RKISP virtual channel。
4. **同步触发**：不要塞进四份 sensor 驱动里；建立独立 PWM/trigger 控制层，或由用户态通过 PWM character/sysfs/debugfs（取决于 BSP）统一配置。

### 4.4 硬件触发

原理图显示 `PWM1_CH0_M0_LED` 先经过 TXS0102 电平转换，再通过 1:4 缓冲形成 `CSI_TRIGGER1~4`。建议：

- DTS 中只启用一个 PWM 控制器和对应 pinctrl；
- 用硬件 PWM 产生稳定脉冲，避免用 GPIO bit-banging；
- 初期用固定频率/占空比验证示波器波形；
- 后续若应用需要原子化配置，可增加很薄的 platform driver，提供频率、脉宽、启停和时间戳接口；
- 不要同时启用占用同一复用脚的 LED 功能。

## 5. 推荐 DTS 组织方式

不要直接覆盖官方开发板 DTS。建议结构如下（实际文件名以 SDK 为准）：

```text
rk3576.dtsi                         SoC 公共定义，尽量不改
mlk-cr03-core.dtsi                 核心模块：PMIC/eMMC/DDR相关外围
rk3576-mlk-devboard.dts            官方开发板，保留作为参考
rk3576-omniego.dts                 你的最终板级入口
rk3576-omniego-camera.dtsi         四路 CSI 与触发
rk3576-omniego-peripherals.dtsi    USB/RTC/audio/LCD/fan/keys/charger
```

如果官方 SDK 没有单独的 `mlk-cr03-core.dtsi`，第一步应从官方开发板 DTS 中抽取“核心模块必需节点”，而不是把整份开发板 DTS 作为永久父文件。

每个外设节点至少核对：

- SoC 控制器实例是否正确；
- pinctrl mux 是否与原理图网络名一致；
- I/O 电压域是否正确；
- reset/PWDN/enable 的有效电平；
- clock、assigned-clock-rates；
- regulator supply 引用；
- interrupt controller、GPIO bank、触发极性；
- `status`；
- media graph 的 port/endpoint 是否成对。

## 6. 驱动开发优先级

### P0：不写新驱动即可完成

- UART console。
- eMMC/TF Card。
- PWM fan。
- ADC keys、GPIO/PWM LED。
- USB host/OTG、CH334F Hub。
- HDMI。
- I2C/SPI/PWM/GPIO 控制器。

这些应优先通过 DTS 和已有内核驱动完成。

### P1：先确认芯片型号，再复用现有驱动

- FUSB302 类 Type-C 控制器。
- ES8388 类音频 Codec。
- RTC U701。
- BQ2589x 类充电管理 U901。
- USB Wi-Fi 模块内部芯片。
- LCD 触摸控制器。

优先在 `kernel/drivers/`、Rockchip BSP 补丁和官方开发板 DTS 中查找 compatible。只有型号确定且现有驱动不支持时才修改驱动。

### P2：很可能需要适配或新增

- 实际四目 camera sensor 驱动及寄存器表。
- 特定 MIPI DSI 屏的初始化序列/面板驱动。
- 四路硬件同步触发的统一控制接口。
- 若 U901 不是内核已有型号，则需要 power_supply/charger 驱动。

## 7. 推荐移植顺序

### 阶段 A：建立可回退基线

1. 保存厂商原始 SDK 和可正常启动的固件。
2. 记录 SDK manifest、内核提交、工具链和完整构建命令。
3. 新建独立 Git 分支，例如 `board/omniego-rk3576`。
4. 保留官方开发板 DTS，不直接在其上长期堆补丁。
5. 确保 UART0 能看到 Loader、U-Boot 和 kernel log。

### 阶段 B：最小启动板

只保留：核心电源、PMIC、eMMC、调试 UART、USB OTG 烧写、watchdog、thermal。先让自研 DTS 稳定启动并挂载根文件系统。

### 阶段 C：基础底板外设

按 TF Card -> USB Host/Hub -> Type-C -> I2C 总线扫描 -> RTC -> fan/keys/LED 的顺序启用。每增加一个节点就保存一次可启动提交。

### 阶段 D：显示与音频

先 HDMI，后 MIPI DSI；先 codec probe，再配置 ASoC routing 和功放 enable。显示、音频都不应阻塞基础启动。

### 阶段 E：相机

1. 先只启用 CAM0，完成 sensor -> CIF/ISP -> `/dev/video*`。
2. 依次验证 CAM1、CAM2、CAM3，确认各自 I2C 地址、MCLK、PWDN 和 lane。
3. 再验证 CAM1/CSI2 的 2+2 lane split。
4. 最后启用四路并发，检查带宽、ISP 资源、DMA/IOMMU、丢帧和温升。
5. 最后接入 PWM 硬触发，测量四路曝光/帧同步偏差。

### 阶段 F：电池与功耗

确认 charger 型号后完成充电、电池状态、OTG、IRQ 和关机策略。之后再做 suspend/resume、wakeup source 和功耗调优。

## 8. 合理裁剪方案

### 8.1 第一轮只裁 DTS

把官方开发板上不存在的设备设为 disabled，例如双网口、PCIe/M.2、4G/5G、CAN、RS485、官方 SDIO Wi-Fi/BT、额外 CSI/DSI 等。不要删除源代码。

### 8.2 第二轮裁内核配置

基于启动和功能日志确认未使用后，再关闭：

- 不存在的网卡 PHY、PCIe endpoint、CAN、RS485 等驱动；
- 不使用的 camera sensor、panel、touch、codec；
- 不需要的文件系统、USB gadget function 和调试选项。

以下内容应长期保留：

- Rockchip clock/reset/pinctrl/regulator/IOMMU；
- eMMC/SD、USB OTG、UART console；
- thermal、watchdog、RTC、input；
- DRM、V4L2/media、RKCIF/RKISP（项目核心功能）；
- 固件升级和救砖所需功能。

### 8.3 第三轮裁根文件系统

- 删除官方演示应用、无关桌面组件和不使用的网络服务；
- 保留 `i2c-tools`、`media-ctl`、`v4l2-ctl`、`libcamera`/GStreamer（按应用栈）、`evtest`、`alsa-utils`、`lsusb`、`devmem` 或同类诊断工具；
- 量产前再决定是否去掉 debugfs、perf、strace 等调试能力。

### 8.4 用证据裁剪

不要凭文件名删除驱动。至少结合：

- `dmesg`、`lsmod`、`/sys/bus/*/devices`；
- `lsusb -nn`、`i2cdetect`；
- `media-ctl -p`、`v4l2-ctl --all`；
- `cat /sys/kernel/debug/clk/clk_summary`；
- `fdtdump`/`dtc` 反编译最终 DTB；
- 启动耗时和镜像大小对比。

## 9. 建议的验证清单

| 阶段 | 验证内容 | 通过标准 |
|---|---|---|
| Boot | Loader/U-Boot/kernel/rootfs | 冷启动、重启、掉电重复稳定 |
| 电源 | 5 V/3.3 V/2.8 V/1.8 V | 电压、纹波、时序符合设计 |
| I2C | I2C0/2/3/4/5/7/8/9 | 地址稳定，无持续 NACK/总线锁死 |
| USB | OTG、Host、CH334F、Wi-Fi | 热插拔、枚举、持续传输稳定 |
| TF | SDMMC0 | 插拔、读写、断电恢复 |
| 显示 | HDMI、DSI | mode 正确，无花屏/ESD 后死机 |
| 音频 | codec、MIC、耳机、双功放 | 录放音、路由、pop noise 可接受 |
| Camera | 单路/双路/四路 | media graph 正确，长时间无丢帧 |
| Sync | 四路 trigger | 示波器测偏斜及相机帧时间戳 |
| Battery | charge/OTG/IRQ/ADC | 充放电状态和保护路径正确 |
| Thermal | CPU/ISP/NPU 压力 | 风扇调速、温控和降频策略正确 |

## 10. 当前还缺的决定性信息

在开始写代码前，还需要：

1. 完整 SDK 源码路径、SDK 版本、内核版本和现有构建命令。
2. 四个 camera sensor 的准确型号、I2C 地址、晶振/MCLK 要求和寄存器初始化表。
3. U901 充电芯片、U701 RTC、U101 Type-C 控制器的 BOM 精确料号。
4. LCD 面板和触摸 IC 型号、分辨率、时序、DSI 初始化命令。
5. USB Wi-Fi 上电后的 `lsusb -nn` 结果。
6. 官方开发板当前实际使用的 DTS/DTB 文件名。
7. 自研板 UART 完整启动日志和 `/proc/device-tree/model`。

拿到 SDK 后，下一步应先做“源码树审计”：定位实际板级 DTS、defconfig、loader 配置、镜像打包脚本和已有同型号驱动，然后形成逐文件修改清单，再开始改代码。
