# RK3576 Ubuntu 24.04 P1 最小 rootfs 阶段记录

## 1. 阶段结论

P1 最小 Ubuntu rootfs 阶段完成。

本阶段已经证明：在不更换厂家 Loader、U-Boot、boot.img、Linux 6.1.99、DTB 和 parameter/分区表的前提下，只替换 eMMC 的 rootfs 分区，即可启动 Ubuntu 24.04 LTS arm64，并通过 RK3576 调试串口登录系统。

本阶段不包含 Mali GPU、MPP/RGA、RKAIQ、摄像头和 RKNPU2 用户态软件栈迁移。这些能力属于后续阶段。

## 2. 阶段目标与完成情况

| 目标 | 结果 | 说明 |
| --- | --- | --- |
| Ubuntu 24.04 arm64 rootfs | 通过 | `systemd` 为 ARM aarch64 ELF |
| eMMC rootfs 挂载 | 通过 | `/dev/mmcblk0p6` 以 ext4 挂载为 `/` |
| systemd 启动 | 通过 | systemd 255.4 进入 `multi-user.target` |
| RK3576 串口登录 | 通过 | `serial-getty@ttyFIQ0.service` 启动成功 |
| `linaro` 用户登录 | 通过 | 成功进入 Ubuntu shell |
| 内核版本保持不变 | 通过 | 仍使用厂家 Linux 6.1.99 |
| 内核模块 | 通过 | 镜像包含 159 个 `.ko` 和 depmod 索引 |
| 固件 | 通过 | 镜像包含约 17 MiB firmware |
| OEM/userdata 分区 | 通过 | 两个 ext4 分区均成功挂载 |
| NetworkManager | 通过 | 服务启动；接口连接状态需按现场网线继续验证 |
| SSH | 已修复配置 | 首次启动因 host key 生成顺序失败，修复已进入构建脚本 |
| root remount | 已修复配置 | 首次启动因短 PARTUUID 失败，已改用完整 PARTUUID |

## 3. 保持不变和实际替换的内容

保持厂家基线：

```text
Loader
U-Boot
boot.img
Linux 6.1.99
RK3576 EVB1 V10 DTB
parameter/分区表
```

本阶段只替换：

```text
rootfs 分区：mmcblk0p6
原系统：Debian 12 bookworm
新系统：Ubuntu 24.04 LTS Noble arm64
```

rootfs 分区标识：

```text
PARTUUID=614e0000-0000-4b53-8000-1d28000054a9
```

## 4. P1 构建产物

Ubuntu rootfs 镜像：

```text
output/ubuntu-noble/rootfs.ext4
```

镜像属性：

```text
格式：ext4
卷标：rootfs
容量：3 GiB
架构：arm64
系统：Ubuntu 24.04 LTS
```

首次通过离线检查的镜像 SHA256：

```text
58ada5e740adaf15d3100d1c5f62a21f4ed95b8201be81b3d89169b8cd599acd
```

说明：后续只要重新生成镜像，ext4 UUID 和 SHA256 都会变化，应以同一构建目录下的以下文件为准：

```text
output/ubuntu-noble/manifests/rootfs.ext4.sha256
```

对应构建实现：

```text
ubuntu/build-minimal-rootfs.sh
ubuntu/configure-target.sh
ubuntu/manifests/base.packages
```

## 5. 实机启动日志证据

### 5.1 rootfs 挂载成功

```text
[    4.966915] EXT4-fs (mmcblk0p6): recovery complete
[    4.967503] EXT4-fs (mmcblk0p6): mounted filesystem with ordered data mode
[    4.972625] Run /sbin/init as init process
```

这证明烧入 `mmcblk0p6` 的镜像是内核可识别和可挂载的 ext4 rootfs，之前论坛整盘镜像导致的 `VFS: Unable to mount root fs` 问题不再存在。

### 5.2 Ubuntu systemd 接管成功

```text
[    5.104650] systemd 255.4-1ubuntu8.17 running in system mode
[    5.104716] Detected architecture arm64
[    5.110077] Hostname set to <rk3576-ubuntu>
[  OK  ] Reached target multi-user.target - Multi-User System.
```

### 5.3 串口和用户登录成功

```text
[  OK  ] Started serial-getty@ttyFIQ0.service - Serial Getty on ttyFIQ0.

Ubuntu 24.04 LTS rk3576-ubuntu ttyFIQ0
rk3576-ubuntu login: linaro
Welcome to Ubuntu 24.04 LTS (GNU/Linux 6.1.99 aarch64)
linaro@rk3576-ubuntu:~$
```

这证明 Ubuntu 用户空间、PAM、用户账号、shell 和 RK3576 串口 getty 均可以正常工作。

### 5.4 基础分区和网络服务

```text
[  OK  ] Mounted oem.mount - /oem.
[  OK  ] Mounted userdata.mount - /userdata.
[  OK  ] Started NetworkManager.service - Network Manager.
```

启动后的接口名为：

```text
end0
end1
```

采集日志时两个接口均为 `DOWN`，说明 NetworkManager 服务正常但尚未建立有效链路。需要结合实际网线、PHY 端口和 DHCP 环境继续验证，不能仅凭服务启动判定网络业务通过。

## 6. 问题一：首次生成的镜像缺少内核模块

### 6.1 现象

首次镜像生成后：

```text
output/kernel-modules/lib/modules/6.1.99/
```

已经存在 159 个内核模块，但：

```text
output/ubuntu-noble/rootfs/lib/modules/6.1.99/
```

不存在。

### 6.2 根因

构建脚本自动发现模块目录时，多取了一层 `lib`：

```text
实际模块根目录：output/kernel-modules
错误推导结果：output/kernel-modules/lib
错误检查路径：output/kernel-modules/lib/lib/modules
```

脚本没有找到模块后只输出 warning，仍继续生成了不完整镜像。

### 6.3 解决方式

修正 `KERNEL_MODULES_DIR` 推导，使其指向：

```text
output/kernel-modules
```

同时将“模块目录不存在”从 warning 改为构建失败，禁止输出缺少模块的镜像。

模块复制后在 chroot 中针对每个 kernel release 执行：

```bash
depmod 6.1.99
```

### 6.4 修复验证

```text
内核模块数量：159
模块目录大小：约 23 MiB
modules.dep：存在
modules.alias：存在
```

## 7. 问题二：chroot `/dev` 挂载残留导致无法删除输出

### 7.1 现象

重新构建前删除旧输出时出现：

```text
rm: cannot remove 'output/ubuntu-noble/rootfs/dev': Device or resource busy
```

`findmnt` 显示同一 rootfs `/dev` 存在两层挂载。

### 7.2 根因

旧版 `configure-target.sh` 在已经进入 chroot 后执行：

```bash
mount --bind /dev /dev
```

chroot 内的源和目标实际上指向同一个 rootfs `/dev`，形成自绑定叠加挂载。退出清理只卸载一层，另一层残留，导致目录 busy。

### 7.3 临时清理方式

```bash
sudo umount -R "$PWD/output/ubuntu-noble/rootfs/dev"
sudo umount -R "$PWD/output/ubuntu-noble/rootfs/dev"
sudo umount -R "$PWD/output/ubuntu-noble/rootfs/proc" 2>/dev/null || true
sudo umount -R "$PWD/output/ubuntu-noble/rootfs/sys" 2>/dev/null || true
```

确认无残留：

```bash
findmnt -rn -o TARGET | grep "$PWD/output/ubuntu-noble/rootfs"
```

无输出后才执行：

```bash
sudo rm -rf output/ubuntu-noble
```

### 7.4 永久修复

挂载操作移到宿主机的 `build-minimal-rootfs.sh`：

```bash
mount -t proc proc "$ROOTFS_DIR/proc"
mount -t sysfs sysfs "$ROOTFS_DIR/sys"
mount --rbind /dev "$ROOTFS_DIR/dev"
mount --make-rslave "$ROOTFS_DIR/dev"
```

新增统一清理函数，并通过 `trap ... EXIT` 保证正常结束或中途失败时均执行递归卸载。

## 8. 问题三：`systemd-remount-fs.service` 启动失败

### 8.1 现象

首次 Ubuntu 启动日志：

```text
[FAILED] Failed to start systemd-remount-fs.service
```

系统仍然能够继续进入 `multi-user.target`，因为内核已经按照启动参数以读写方式挂载 rootfs，但该失败不能保留为正式镜像状态。

### 8.2 根因

旧版 `/etc/fstab` 使用短 PARTUUID：

```text
PARTUUID=614e0000-0000 / ext4 defaults,noatime 0 1
```

厂家内核启动参数可以使用该短值定位 rootfs，但 systemd 用户空间通过 `/dev/disk/by-partuuid/` 解析时需要完整 PARTUUID。

### 8.3 解决方式

改为完整值：

```text
PARTUUID=614e0000-0000-4b53-8000-1d28000054a9 / ext4 defaults,noatime 0 1
```

板上临时修复命令：

```bash
sudo sed -i \
's#PARTUUID=614e0000-0000 /#PARTUUID=614e0000-0000-4b53-8000-1d28000054a9 /#' \
/etc/fstab

sudo systemctl daemon-reload
sudo systemctl restart systemd-remount-fs.service
```

该修改已写入 `ubuntu/configure-target.sh`，后续构建自动生效。

## 9. 问题四：`ssh.service` 首次启动失败

### 9.1 现象

```text
[FAILED] Failed to start ssh.service - OpenBSD Secure Shell server.
```

### 9.2 根因

为避免所有设备使用相同 SSH host key，构建阶段删除了：

```text
/etc/ssh/ssh_host_*
```

原 SSH unit 已包含：

```text
ExecStartPre=/usr/sbin/sshd -t
```

旧版 drop-in 只是追加：

```text
ExecStartPre=/usr/bin/ssh-keygen -A
```

systemd 会先执行原 unit 的 `sshd -t`，然后才执行追加项。因此首次启动时配置检查因 host key 不存在提前失败，生成 key 的命令没有机会执行。

### 9.3 板上临时解决方式

```bash
sudo ssh-keygen -A
sudo /usr/sbin/sshd -t
sudo systemctl restart ssh
sudo systemctl status ssh --no-pager
sudo ss -lntp | grep ':22'
```

### 9.4 永久修复

在 drop-in 中先清空原 `ExecStartPre` 列表，再按正确顺序重新定义：

```ini
[Service]
ExecStartPre=
ExecStartPre=/usr/bin/ssh-keygen -A
ExecStartPre=/usr/sbin/sshd -t
```

该修改已写入 `ubuntu/configure-target.sh`。

## 10. 离线镜像检查记录

烧录前完成以下检查：

### 10.1 镜像格式

```text
Linux rev 1.0 ext4 filesystem data
volume name "rootfs"
```

### 10.2 文件系统一致性

```text
Pass 1: Checking inodes, blocks, and sizes
Pass 2: Checking directory structure
Pass 3: Checking directory connectivity
Pass 4: Checking reference counts
Pass 5: Checking group summary information
```

没有发现 ext4 错误。

### 10.3 用户空间架构

```text
/usr/lib/systemd/systemd:
ELF 64-bit LSB pie executable, ARM aarch64
```

### 10.4 关键服务配置

```text
serial-getty@ttyFIQ0.service：enabled
NetworkManager.service：enabled
ssh.service：enabled
默认 target：multi-user.target
```

## 11. 非 P1 引入的 BSP 已知问题

以下问题在厂家 Debian/P0 基线中已经存在，不应归因于 Ubuntu rootfs：

- IMX415 I2C sensor ID 读取为 `000000`，Camera sensor 链路不通。
- RKCIF 多次报告 `get remote terminal sensor failed`。
- Goodix 触摸控制器 I2C 通信失败。
- 两个 RKVENC 核心的 OPP/devfreq 初始化失败。
- PCIe link 初始化失败。
- `regulatory.db` 缺失。
- 部分 SPI/I2C pin 存在占用冲突。

以下 Ubuntu 启动警告当前不阻塞 P1：

```text
Failed to find module 'autofs4'
local system does not support BPF/cgroup firewalling
```

后续根据是否使用 autofs 和 systemd BPF 防火墙功能决定补模块、禁用功能或加入已知警告白名单。

## 12. P1 遗留验证项

P1 核心启动链已经通过。进入 P2 前或 P2 集成测试时，应补充保存以下结果：

```bash
systemctl --failed --no-pager
systemctl status ssh --no-pager
ss -lntp | grep ':22'
findmnt /
nmcli device status
ip addr
ip route
```

建议连续冷/热重启 10 次，确认：

- 每次均能挂载 `mmcblk0p6`。
- 每次均能进入 `multi-user.target`。
- `ttyFIQ0` 每次均出现登录提示。
- SSH host key 只在首次启动生成，后续保持稳定。
- rootfs 不发生新的 recovery 或一致性错误。

## 13. 下一阶段

下一阶段为 P2 SDK 构建系统集成：

- 拆分 `mk-base-ubuntu.sh`、`mk-rootfs-noble.sh` 和 `mk-image.sh`。
- 新增 `Config.in.ubuntu` 和 `check-ubuntu.sh`。
- 增加 `RK_ROOTFS_SYSTEM_UBUNTU` 等 Kconfig 配置。
- 在 `mk-rootfs.sh` 增加 `build_ubuntu()`。
- 实现并验证 `./build.sh ubuntu`。
- 输出 `output/<board>/ubuntu/images/rootfs.ext4`。
- 复用现有 firmware/update.img 打包流程。

P2 完成前仍不开始 GPU、MPP/RGA、Camera 和 NPU 用户态栈的正式迁移。
