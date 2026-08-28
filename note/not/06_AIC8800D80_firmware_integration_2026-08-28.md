# 06 AIC8800D80 驱动固件接入记录

## 1. 问题来源

板端 USB 已枚举 `a69c:8d80`（AIC Wlan），内核模块也已加载，但日志报错：

```text
aic_load_firmware: fw_patch_table_8800d80_u02.bin file failed to open
```

结论：驱动存在，AIC8800D80 固件未进入 Ubuntu rootfs。

## 2. 厂商文件

厂商提供 11 个文件，覆盖 U02 版本的 patch table、ADID、FMAC、LMAC、校准和蓝牙过滤功能。原始文件目录：`驱动固件/`。

SHA256 清单由接入时生成，便于后续版本追踪：

```text
5ff184105fdc4c4679e026418f4da293efec8df02a3a3ca22cee723c17df4a60  fw_patch_table_8800d80_u02.bin
a526cbd02fcdc495f049f3ad6b5933cb08cd984b16790c716a060d582fee1a56  fw_adid_8800d80_u02.bin
4ad4eede4d347c45ed61b23508e7843dc884f0e411bf957f95410001d0cfc4d0  fw_patch_8800d80_u02.bin
9e88232fc08cac8766d445e96f211ab69a8d2adb9fc0ce8eef0747acf453e75  fmacfw_8800d80_u02.bin
2103ade9a155cd2ddbe653b17c89d976859f5c88db5e199dd75173a2e2dda13d  fmacfw_8800d80_h_u02.bin
7e97b34087ff4246aa965abe3fbd7ccbc34eb80bae1bbff7952647224a819873  fmacfw_8800d80_u02_ipc.bin
9e28a54d3c78d49015d84957b95cc6003407aeb7e973387e97129a7f8cf89933  lmacfw_rf_8800d80_u02.bin
12dfaa75ea0c3bf9144a06fc54cdd5252017a761940c9a34946f8fdbf4135624  fw_ble_scan_ad_filter.bin
4ede0b9c1a224aca0d37de4968d8b034c07629b2d77eaaa91a4d2103d56879b6  calibmode_8800d80.bin
```

## 3. SDK 接入实现

文件已放入：

```text
ubuntu/overlay-firmware/vendor/etc/firmware/
```

`ubuntu/mk-rootfs-noble.sh` 在基础 Debian 固件复制后执行 overlay：

- 安装到 `/vendor/etc/firmware/`，匹配厂商 AIC 驱动的实际请求路径；
- 同步复制到 `/lib/firmware/`，兼容标准 Linux firmware loader；
- 代码注释说明了两个路径的原因。

## 4. 构建后检查

SDK 源码终端：

```bash
find ubuntu/overlay-firmware/vendor/etc/firmware -type f -printf '%f\n' | sort
./build.sh ubuntu
```

板端烧录后：

```bash
ls -lh /vendor/etc/firmware/fw_patch_table_8800d80_u02.bin
dmesg | grep -iE 'aic|wlan|bluetooth|firmware'
ip -br link
```

成功标准：不再出现 `file failed to open`，并出现 `wlan0` 或 `wlx...`；蓝牙应能通过 `bluetoothctl list` 看到控制器。

## 5. 尚未完成

本次只完成固件进入镜像，尚未在实板上完成重启、Wi-Fi 扫描、联网、蓝牙扫描和长时间稳定性验收。若仍失败，应继续检查模块自动加载、固件文件完整性和 `wifibt-init.service` 日志。

## 6. Wi-Fi 问题排查与解决全流程

### 6.1 现象

Ubuntu 桌面可以启动，但 `ip -br link` 中没有 `wlan0` 或 `wlx...`，`wifibt-init.service` 显示 `active (exited)`，日志同时出现：

```text
Failed to detect Wi-Fi/BT chip!
```

这里要区分“服务进程退出”与“功能成功”：systemd 的 `active (exited)` 只说明脚本返回 0，不能证明无线设备已经注册。

### 6.2 第一层：确认硬件枚举（板端）

```bash
dmesg | grep -iE 'usb|aic|wlan|bluetooth|firmware'
```

关键证据：

```text
idVendor=a69c, idProduct=8d80
Product: AIC Wlan
```

这说明 USB 主控制器、USB Hub 和 AIC 无线芯片均已工作，问题不在 HDMI、NetworkManager 或网线配置。

### 6.3 第二层：确认驱动匹配（源码和板端）

源码路径：

```text
kernel-6.1/drivers/net/wireless/aic8800/aic_load_fw/aicwf_usb.c
```

调用关系：

```text
aicwf_usb_probe()
  -> aicloadfw_chipmatch()
  -> usb_dev->chipid = PRODUCT_ID_AIC8800D80
```

板端日志：

```text
aicloadfw_chipmatch USE AIC8800D80
```

说明 VID/PID 匹配成功，`aic_load_fw.ko` 已经被 USB 驱动绑定。

### 6.4 第三层：确认固件选择与加载

固件名称定义：

```text
kernel-6.1/drivers/net/wireless/aic8800/aic_load_fw/aic_compat_8800d80.h
```

U02 版本选择：

```c
FW_PATCH_TABLE_NAME_8800D80_U02
    = "fw_patch_table_8800d80_u02.bin"
```

固件加载函数：

```text
kernel-6.1/drivers/net/wireless/aic8800/aic_load_fw/aicbluetooth.c
    aic_load_firmware()
        -> request_firmware()
```

原始失败日志：

```text
aic_load_firmware :firmware path = /vendor/etc/firmware/fw_patch_table_8800d80_u02.bin
fw_patch_table_8800d80_u02.bin file failed to open
wrong size of firmware file
```

根因由此确定为：驱动已识别芯片，但 Ubuntu 镜像没有厂商 AIC8800D80 固件。后面的 `bus is not up=0`、`aicwf_bus_deinit` 是失败清理阶段的连带日志。

### 6.5 第四层：为什么没有 `wlan0`

Wi-Fi 主驱动路径：

```text
kernel-6.1/drivers/net/wireless/aic8800/aic8800_fdrv/
```

入口：

```text
rwnx_mod_init()
```

只有在 USB probe、固件读取和固件上传都成功后，驱动才会注册 mac80211/cfg80211 无线接口。因此：

```text
固件读取失败 -> 芯片未启动 -> Wi-Fi 驱动不注册 -> 系统没有 wlan0
```

蓝牙同理，`aic_btusb.ko` 依赖同一套芯片固件初始化，所以 Wi-Fi 固件缺失时蓝牙 HCI 也可能不存在。

### 6.6 修复动作

厂商提供的 11 个文件被纳入：

```text
ubuntu/overlay-firmware/vendor/etc/firmware/
```

`ubuntu/mk-rootfs-noble.sh` 在构建时执行两次安装：

```text
/vendor/etc/firmware/   # 厂商驱动实际请求路径
/lib/firmware/          # Linux 标准 firmware loader 路径
```

这样解决了“文件在 SDK 中存在，但没有进入目标 rootfs”和“驱动查找路径与发行版标准路径不一致”两个问题。

### 6.7 验证闭环（板端）

```bash
ls -lh /vendor/etc/firmware/fw_patch_table_8800d80_u02.bin
lsmod | grep -E 'aic|bluetooth'
ip -br link
rfkill list
nmcli device status
bluetoothctl list
dmesg | grep -iE 'aic|wlan|bluetooth|firmware'
```

成功标准：

1. 固件文件存在且大小非零；
2. 日志不再出现 `file failed to open` 或 `wrong size of firmware file`；
3. 出现 `wlan0`/`wlx...`；
4. `nmcli` 能看到 Wi-Fi 设备；
5. `bluetoothctl list` 能看到 HCI 控制器；
6. 重启后上述状态仍保持。

## 7. 面试八股：这次问题对应的基础知识

### 7.1 驱动、固件和用户态的区别

- **驱动**是运行在内核态的代码，负责 USB 总线、DMA、网卡注册和数据收发；
- **固件**是下载到无线芯片内部 RAM/ROM 的二进制程序，决定芯片能否执行 Wi-Fi/BT 协议；
- **用户态**的 NetworkManager、wpa_supplicant、BlueZ 只管理已经注册成功的网络和蓝牙设备，不能替代内核驱动或芯片固件。

因此“模块已加载”不等于“无线可用”。

### 7.2 Linux USB 驱动匹配机制

USB 设备通过 VID/PID 生成设备标识；驱动的 `usb_device_id` 表匹配成功后，内核调用驱动的 `.probe()`。本案例中：

```text
a69c:8d80 -> aicwf_usb_probe() -> AIC8800D80
```

拔出设备时调用 `.disconnect()`，驱动释放 URB、网络设备和固件相关资源。

### 7.3 `request_firmware()` 的作用

`request_firmware()` 通过 Linux firmware loader 从 rootfs 查找二进制文件，并将其交给驱动。失败常见原因：路径错误、文件缺失、权限错误、文件名/芯片版本不匹配。排查时应先看内核日志中的“实际请求文件名”，不能只看目录是否存在。

### 7.4 mac80211、cfg80211 与 NetworkManager

硬件驱动完成初始化后，通常通过 mac80211/cfg80211 向内核无线子系统注册接口；NetworkManager 再通过 netlink 管理扫描、认证、DHCP 和连接。分层排查顺序应是：

```text
USB 枚举 -> 内核驱动 -> 固件 -> wlan 接口 -> cfg80211 -> NetworkManager -> DHCP
```

本案例故障发生在 `wlan 接口` 之前，所以修改 DHCP 或桌面网络设置没有意义。

### 7.5 面试项目表述

可以这样描述：

> 在 RK3576 Ubuntu 24.04 移植中，定位到 AIC8800D80 USB 无线设备能够完成 VID/PID 枚举和内核驱动匹配，但因厂商固件未随 Debian 到 Ubuntu 的 rootfs 迁移，`request_firmware()` 在 `/vendor/etc/firmware` 查找失败，导致 Wi-Fi/蓝牙初始化中止。通过分析 `aicwf_usb_probe()`、芯片兼容层和 systemd 初始化脚本，将厂商 U02 固件纳入 Ubuntu overlay，并同时兼容 `/vendor/etc/firmware` 与 `/lib/firmware`，建立了从 USB 枚举到 NetworkManager/BlueZ 的验证闭环。

追问时应强调：先用日志确定故障层级，再修改对应层；没有 `wlan0` 时不应直接从 NetworkManager 或 DHCP 入手。

## 8. 命令环境对照

| 操作 | 执行环境 |
|---|---|
| `find ubuntu/...`、`rg ...`、`./build.sh ubuntu` | SDK 源码终端 |
| `dmesg`、`lsmod`、`ip`、`rfkill`、`nmcli`、`bluetoothctl` | 板端 Ubuntu 终端 |
| 检查 `ubuntu/binary` 中是否有固件 | SDK 源码终端 |
| 检查 `/vendor/etc/firmware` 是否存在 | 板端 Ubuntu 终端 |
