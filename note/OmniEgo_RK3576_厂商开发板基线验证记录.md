# OmniEgo RK3576 厂商开发板基线验证记录

## 基本信息

- SDK: MLK SDK RK3576 V1.1.0
- SDK defconfig: `mlk_rk03_rk3576_defconfig`
- Kernel: Linux 6.1.99
- Rootfs: Buildroot 2024.02, ext4
- Board-reported model: Rockchip RK3576 EVB1 V10 Board
- Firmware: `output/firmware/update.img`
- Firmware size: 995 MiB
- Firmware SHA256: `ec716d75cb83de23b6d7a211e9d206acf58450e3c43cc07f8b8ad00b67e4d183`
- Build host: `magine@magine-virtual-machine`
- Build result: PASS
- Flash result: PASS
- Boot result: PASS

## 核心基线结论

自编译 `update.img` 已成功烧录并启动。板端 `RK_BUILD_INFO` 显示本次构建主机信息，U-Boot 版本信息包含本次构建日期，可以排除仍在运行商家旧 rootfs 的情况。

```text
源码编译 -> 固件打包 -> 整包烧录 -> U-Boot -> Linux
-> eMMC -> ext4 rootfs -> Buildroot shell -> Weston/GPU/显示
```

上述核心启动链验证通过，这套厂商 SDK 可作为后续 OmniEgo 底板移植的可信对照基线。

## 已验证项

| 项目 | 结果 | 依据 |
|---|---|---|
| 完整 SDK 编译 | PASS | `build_updateimg` / `build_firmware` / `build_all succeeded` |
| `update.img` 烧录 | PASS | 烧录成功且板端运行本次构建系统 |
| U-Boot/Kernel 启动 | PASS | Linux 6.1.99 正常进入 shell |
| Buildroot rootfs | PASS | Buildroot 2024.02，`/dev/mmcblk0p6` 以 ext4 读写挂载 |
| eMMC | PASS | 29.1 GiB，HS400 Enhanced Strobe，p1-p8 正常枚举 |
| OEM/Userdata | PASS | p7/p8 以 ext4 挂载到 `/oem` 和 `/userdata` |
| 调试串口 | PASS | 可查看启动日志并登录 shell |
| GPU/OpenGL ES | PASS | ARM Mali-G52，OpenGL ES 3.2 |
| DSI 显示 | PASS | 800x1280@60 Hz |
| HDMI 基础输出 | PASS | 成功识别显示器并输出 2560x1440@60 Hz |
| USB Host 基础枚举 | PASS | xHCI、USB 2.0 Hub 和 AIC WLAN 设备正常枚举 |
| CPU/内存/温度 | PASS | ARM64 CPU 枚举正常，约 1.9 GiB 内存，33-34 C |

## 待补充或专项验证

| 项目 | 状态 | 说明 |
|---|---|---|
| 有线网络 | PENDING | eth0/eth1 处于 `NO-CARRIER`，ping 未成功 |
| 系统时间/RTC | PENDING | 未执行时间与断电保持验证 |
| 重启 | PENDING | 未完成 `sync && reboot` 后二次启动验证 |
| Audio | PENDING | PulseAudio 存在 ConsoleKit/DBus 告警，未证明实际播放/录音 |
| Camera | PENDING | 存在多条 remote sensor 和供电配置错误 |
| Touch | PENDING | Goodix I2C 通信失败 |
| PCIe | PENDING | 未连接终端设备时 Link Fail |
| Type-C/PD | PENDING | HUSB311 VID/PID 检查失败 |
| HDMI 热插拔稳定性 | PENDING | 热插拔时出现 `POST_BUF_EMPTY_INTR` |

## 已知日志项

- DTS `model` 显示 EVB1 V10，尚未体现 MLK RK03/OmniEgo 产品名称。
- `gpio3-21` 存在 MIPI CSI 电源与 SPI 引脚请求冲突。
- `regulatory.db` 缺失，可能影响 Wi-Fi 国家码和部分信道。
- 多个未连接或板级未配置外设产生 probe 告警，不影响当前核心启动基线结论。

## 后续动作

1. 完成网络、RTC/时间和重启验证。
2. 保留当前固件、SHA256 和完整启动日志。
3. 以本基线为对照，建立 OmniEgo 专用 defconfig 和 DTS。
4. 按最小启动、基础外设、显示音频、相机的顺序逐项移植。
