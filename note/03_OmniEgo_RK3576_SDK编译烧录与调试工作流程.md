# OmniEgo RK3576 SDK 编译、烧录与调试工作流程

## 1. 文档目的

本文档面向 MLK RK03 RK3576 开发板，总结完整 SDK 的环境准备、配置、编译、打包、烧录、启动验证和问题定位方法。当前阶段的目标不是立即移植 OmniEgo 底板，而是先证明这套厂商 SDK 能为商家开发板生成可启动固件。

```text
原始 SDK 校验
  -> 准备主机环境
  -> 选择正确 defconfig
  -> 全量编译
  -> 检查 update.img
  -> 保留商家恢复镜像
  -> 烧录商家开发板
  -> 串口与外设验证
  -> 记录已验证基线
  -> 再开始 OmniEgo 底板移植
```

## 2. 编译不等于汇编

日常语境中可以说“编译 SDK”，但技术上需要区分：

| 阶段 | 作用 | 常见输入/输出 |
|---|---|---|
| 预处理 | 展开头文件和宏 | `.c` -> `.i` |
| 编译 | 将 C/C++ 转为汇编 | `.c` -> `.s` |
| 汇编 | 将汇编转为目标文件 | `.s` -> `.o` |
| 链接 | 合并目标文件和库 | `.o` -> ELF/可执行文件 |
| 镜像打包 | 按启动和分区规则组装产物 | `Image`/DTB/rootfs -> `*.img` |
| 烧录 | 将镜像写入 eMMC/其他存储 | `update.img` -> 开发板 |

本项目的 `make` 不只编译 C 代码，还会调度 U-Boot、Linux Kernel、Buildroot、Recovery 和 Rockchip 打包工具。

## 3. 当前项目的确定配置

```text
SDK 路径：/home/magine/uisrc/mlk-sdk-3576-v1.1.0
构建主机：Ubuntu 22.04
板级 defconfig：mlk_rk03_rk3576_defconfig
芯片家族：rk3576
U-Boot 配置：rk03
Kernel 架构：arm64
Kernel defconfig：rockchip_linux_defconfig
Kernel DTS：mlk-rk03-rk3576-linux.dts
rootfs：Buildroot，ext4
主固件：output/firmware/update.img
```

这些值来自当前 `output/.config`，不是根据文件名猜测。

## 4. 构建主机准备

### 4.1 资源建议

| 资源 | 最低尝试 | 建议 |
|---|---:|---:|
| CPU | 2 核 | 4~8 核 |
| 内存 | 4 GiB + Swap | 16 GiB |
| 可用磁盘 | 80 GiB | 120 GiB 以上 |
| 文件系统 | ext4 | ext4 |

当前虚拟机为 2 核、3.8 GiB 内存、3.8 GiB Swap、86 GiB 可用空间。可以继续尝试，但编译慢、内存耗尽或磁盘耗尽的概率较高。

### 4.2 当前 Buildroot 基线的一次性依赖安装

```bash
sudo apt update
sudo apt install -y \
  build-essential gcc g++ make \
  autoconf automake libtool pkg-config \
  bc bison flex device-tree-compiler \
  python3 python-is-python3 \
  rsync git wget curl ca-certificates \
  file patch diffutils findutils \
  perl cpio unzip zip tar gzip bzip2 xz-utils \
  lz4 lzop zstd \
  expect expect-dev fakeroot chrpath \
  libc6-dev libssl-dev libgmp-dev libmpc-dev \
  libncurses-dev libelf-dev dwarves \
  swig gettext texinfo uuid-dev
```

这份清单基于当前 SDK 的 `check-sdk.sh`、`check-loader.sh`、`check-kernel.sh`、`check-buildroot.sh` 和 Buildroot 主机依赖检查脚本。它针对当前的 Buildroot 基线，没有强制安装 Debian/Yocto 才需要的 `debootstrap`、`qemu-user-static` 和 `binfmt-support`。

安装后执行一次检查：

```bash
for cmd in gcc g++ make rsync python3 python dtc bc bison flex \
  cpio unzip wget git perl patch file unbuffer fakeroot chrpath \
  lz4 lzop zstd swig; do
  command -v "$cmd" >/dev/null || echo "MISSING: $cmd"
done

make --version | head -1
dtc --version
lz4 --version
```

正常情况下不应输出任何 `MISSING`。SDK 要求 GNU Make 不低于 4.0；Ubuntu 22.04 的 GNU Make 4.3 满足要求。

若未来切换到 Debian rootfs，再补充：

```bash
sudo apt install -y debootstrap qemu-user-static binfmt-support
```

不建议一次无判断安装来源不明的软件。如果 SDK 后续报缺失依赖，应记录第一个错误并精确补充。

### 4.3 Python 2 兼容环境

这套旧版 Rockchip U-Boot 的 `u-boot/make.sh` 显式使用 `python2`。Ubuntu 22.04 默认不再提供 Python 2，建议只为 SDK 构建安装 Python 2.7.18：

```bash
cd /tmp
wget https://www.python.org/ftp/python/2.7.18/Python-2.7.18.tgz
tar -xf Python-2.7.18.tgz
cd Python-2.7.18

sudo apt install -y libsqlite3-dev zlib1g-dev libffi-dev \
  libreadline-dev libbz2-dev libncurses5-dev

./configure --prefix=/home/magine/.local/python2.7
make -j2
make install

export PATH=/home/magine/.local/python2.7/bin:$PATH
python2 --version
```

预期为 `Python 2.7.18`。不要将 `/usr/bin/python3` 伪装成 `python2`，否则可能在打包阶段生成错误产物。

持久化当前用户的 PATH：

```bash
echo 'export PATH=/home/magine/.local/python2.7/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

## 5. 首次全量编译

### 5.1 确认基础 SDK

```bash
cd /home/magine/uisrc
sha256sum -c \
  /home/magine/uisrc/omniego-rk3576-bsp/manifests/base-sdk.sha256
```

预期输出为 `mlk-sdk-3576-v1.1.0.tar.gz: OK`。它证明保存的压缩包没有变化；不代表已解压的工作目录没有被修改。

### 5.2 选择板级配置

```bash
cd /home/magine/uisrc/mlk-sdk-3576-v1.1.0
make mlk_rk03_rk3576_defconfig
```

也可以直接执行 `make` 后在菜单中选择 `2. mlk_rk03_rk3576_defconfig`，但显式命令更容易记录和自动化。

检查配置：

```bash
readlink -f output/defconfig
grep -E '^RK_(DEFCONFIG|CHIP|ROOTFS_SYSTEM|KERNEL_DTS_NAME)=' \
  output/.config
```

### 5.3 执行全量编译

```bash
make 2>&1 | tee first-build.log
```

顶层 `make` 会调用 `build.sh`。当前 SDK 的全量流程为：

```text
misc
 -> loader/U-Boot
 -> Linux kernel + DTB + modules
 -> Buildroot rootfs
 -> recovery
 -> firmware 分区镜像
 -> update.img
 -> release 信息和日志
```

`tee` 会同时在终端显示输出并写入日志。SDK 自身也会在 `output/sessions/<时间>/` 和 `output/log/` 保存日志。

### 5.4 监控资源

另开终端执行：

```bash
free -h
df -h /home/magine/uisrc
top
```

若日志只显示 `Killed`，并没有正常的编译错误，常见原因是 OOM（内存耗尽）。若出现 `No space left on device`，则是磁盘或 inode 耗尽。

## 6. 产物和启动链

完整编译后检查：

```bash
find output/firmware -maxdepth 1 -type f -printf '%f %s bytes\n' | sort
ls -lh output/firmware/update.img
sha256sum output/firmware/update.img
```

常见产物：

| 产物 | 作用 |
|---|---|
| `MiniLoaderAll.bin` | BootROM 之后的初始加载器，初始化 DDR/存储 |
| `uboot.img` | U-Boot 启动引导程序 |
| `boot.img` | 通常包含 Kernel、DTB 及相关启动数据 |
| `recovery.img` | 恢复系统 |
| `rootfs.img` | Buildroot 生成的 ext4 根文件系统 |
| `misc.img` | 启动/恢复控制信息 |
| `parameter.txt` | 分区布局描述 |
| `update.img` | 整包升级镜像 |

概念性启动链：

```text
SoC BootROM
 -> MiniLoader/SPL
 -> U-Boot
 -> Linux Image + DTB
 -> 挂载 rootfs
 -> init/service
 -> 用户空间应用
```

串口没有任何输出时先查电源、晶振、BootROM/Loader 和 UART 引脚；有 U-Boot 但没有 Kernel 时查 `boot.img`、内核加载地址和 DTB；Kernel 启动后挂载失败则查分区、rootfs 类型、根设备参数和存储驱动。

## 7. 增量构建常用命令

先查 SDK 当前支持的目标：

```bash
make help
```

| 目的 | 命令 |
|---|---|
| 选择板级配置 | `make mlk_rk03_rk3576_defconfig` |
| 全量构建所有镜像 | `make` |
| 只构建 U-Boot/Loader | `make uboot` |
| 只构建 Linux Kernel | `make kernel` |
| 只构建内核模块 | `make modules` |
| 打开内核配置 | `make kernel-config` |
| 只构建 Buildroot rootfs | `make buildroot` |
| 打开 Buildroot 配置 | `make buildroot-config` |
| 只构建 Recovery | `make recovery` |
| 组装分区固件 | `make firmware` |
| 重新打包整体镜像 | `make updateimg` |
| 查看分区 | `make print-parts` |
| 保存 SDK 级简化配置 | `make savedefconfig` |

典型增量流程：

```text
只改 DTS：make kernel -> make firmware -> make updateimg
只改 U-Boot：make uboot -> make firmware -> make updateimg
只改 Buildroot 包：make buildroot -> make firmware -> make updateimg
改分区表：重新检查 parameter/package-file，然后全量构建和整包烧录
```

修改模块后只执行 `make updateimg` 是不够的：`updateimg` 只重新组包现有镜像，不会代替内核或 rootfs 的编译。

## 8. 清理命令的使用原则

```bash
make clean
```

这个 SDK 的顶层 `clean` 会进入 `cleanall`，可删除大量 `output` 内容。它不是普通的“清理一点临时文件”，不要在遇到任何错误时就盲目执行。

正确原则：

1. 先保留失败日志。
2. 先判断是缺少主机依赖、源码错误还是旧产物污染。
3. 只清理受影响的模块。
4. 确实需要重建基线时才进行全量清理。

## 9. 烧录前的强制检查

烧录会改写开发板存储，必须先满足：

- 确认开发板是 MLK RK03 RK3576 或商家明确说明与该 defconfig 兼容；
- 保留商家的原始可启动镜像和对应烧录工具；
- 掌握 Loader 和 Maskrom 进入方法；
- 确认 USB 线、供电和串口连接稳定；
- 确认 `update.img` 非空且 SHA256 已记录；
- 尽量首次使用商家已验证的 Windows/Linux 烧录流程。

检查工具和设备：

```bash
cd /home/magine/uisrc/mlk-sdk-3576-v1.1.0
ls -lh output/firmware/update.img
sha256sum output/firmware/update.img
tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool -h
sudo tools/linux/Linux_Upgrade_Tool/Linux_Upgrade_Tool/upgrade_tool ld
```

`ld` 只用于列出设备。若没有检测到 Loader/Maskrom 设备，不要继续烧录。

## 10. 烧录方式

### 10.1 首次基线验证：整包烧录

根目录 `rkflash.sh` 是到 `device/rockchip/common/scripts/rkflash.sh` 的软链接。整包烧录命令为：

```bash
cd /home/magine/uisrc/mlk-sdk-3576-v1.1.0
sudo ./rkflash.sh update
```

该命令会调用 `upgrade_tool uf rockdev/update.img`。它是会修改板载存储的操作，只有在板型、固件和恢复方法都已确认后才执行。

### 10.2 开发阶段：单分区烧录

```bash
sudo ./rkflash.sh uboot
sudo ./rkflash.sh boot
sudo ./rkflash.sh rootfs
sudo ./rkflash.sh recovery
sudo ./rkflash.sh rd
```

单分区烧录速度更快，但只适用于分区表和其他分区已知兼容的情况。修改 `parameter.txt`、存储布局或 A/B 策略后，不能随意只烧单个分区。

高风险命令：

```bash
sudo ./rkflash.sh erase
```

`erase` 会擦除存储内容。它不是常规烧录步骤，本文仅用于识别命令，不建议在基线验证中执行。

## 11. 烧录后验收

首次启动必须连接调试串口并保存完整日志。不能只以“屏幕亮了”或“能 ping”判定 SDK 无问题。

验收项：

```text
[ ] BootROM/Loader 没有循环重启
[ ] U-Boot 输出和倒计时正常
[ ] Kernel 解压并启动
[ ] 设备树板型与实际板卡一致
[ ] eMMC 和分区识别正常
[ ] ext4 rootfs 挂载成功
[ ] init 进程启动，可登录 shell
[ ] 网口/USB/关键外设与商家镜像表现对比完成
[ ] reboot/poweroff 行为正常
[ ] dmesg 无持续性供电、时钟、存储或文件系统报错
```

板端常用命令：

```bash
uname -a
cat /proc/device-tree/model
cat /proc/cmdline
dmesg -T | less
lsblk -f
mount
df -h
free -h
ip addr
lsusb
cat /proc/interrupts
```

收集关键错误：

```bash
dmesg -T | grep -iE 'error|fail|timeout|panic|mmc|ext4|regulator'
```

`grep` 结果需人工判断：启动时的某些可选设备 `probe failed` 不一定影响主功能，而 eMMC、rootfs、PMIC 和关键时钟错误则应优先处理。

## 12. 失败定位流程

```text
先找第一个真实 ERROR
  -> 判断是主机环境、编译、打包还是板端启动
  -> 找该阶段的完整日志
  -> 做最小修正
  -> 重建受影响模块
  -> 重新打包
  -> 验证
```

常用日志命令：

```bash
find output/sessions -maxdepth 2 -type f -printf '%T@ %p\n' | sort -nr | head
tail -n 100 first-build.log
grep -nE '(^|[^A-Za-z])(ERROR|FATAL|Error|error:)' first-build.log | head -50
```

不要只看最后的 `build_all failed`。它往往是上层汇总错误，真正原因通常在更早的第一个错误中，例如本次的 `Your python2 is missing for U-Boot`。

## 13. 常用 Linux 和 Git 命令

### 13.1 文件和搜索

```bash
pwd                              # 当前目录
ls -lah                          # 包含隐藏文件的详细列表
du -sh output buildroot/output   # 查看目录大小
df -h .                          # 查看磁盘剩余空间
find output -name 'update.img'   # 按文件名查找
rg -n 'RK_KERNEL_DTS' output/.config  # 搜索文本并显示行号
file output/firmware/boot.img    # 识别文件类型
sha256sum FILE                   # 计算文件唯一性校验
```

### 13.2 日志阅读

```bash
less FILE                        # 分页查看，q 退出，/ERROR 搜索
tail -f FILE                     # 持续跟踪文件末尾
tee FILE                         # 屏幕和文件同时输出
command 2>&1 | tee FILE          # 合并标准错误后保存
```

### 13.3 Git 开发循环

```bash
git status
git diff
git add <明确文件路径>
git diff --cached
git commit -m "<模块>: <修改目的>"
git push
git log --oneline --decorate -10
```

尖括号内容是占位说明，不能原样输入 Bash。

## 14. 常见“八股”知识问答

### 14.1 什么是交叉编译？

在 x86_64 Ubuntu 主机上生成 ARM64 RK3576 可执行文件，就是交叉编译。主机程序使用本机 `gcc`，目标程序使用   `aarch64-none-linux-gnu-gcc` 等交叉工具。

### 14.2 什么是 toolchain？

工具链是编译器、汇编器、链接器、库和调试工具的集合。前缀中的 `aarch64` 表示 64 位 ARM 目标架构，`none-linux-gnu` 表示 GNU/Linux ABI 环境。

### 14.3 defconfig 和 `.config` 有什么区别？

`defconfig` 是人工维护的精简配置起点；`.config` 是 Kconfig 展开默认值和依赖后的实际构建配置。不应只复制临时 `.config` 作为长期版本管理方案，应将经过审查的改动保存回 defconfig。

### 14.4 DTS、DTSI 和 DTB 是什么？

`DTS` 是开发板设备树源文件，`DTSI` 是可复用的包含片段，`DTB` 是由 `dtc` 编译后供 U-Boot/Kernel 使用的二进制设备树。设备树描述硬件，驱动实现软件行为。

### 14.5 U-Boot 做什么？

U-Boot 完成较早期硬件初始化，选择启动介质，读取 Kernel/DTB，准备 bootargs 并跳转到 Linux Kernel。它也常提供烧录、网络启动和恢复能力。

### 14.6 Kernel 和 rootfs 是什么关系？

Kernel 管理 CPU、内存、设备和进程；rootfs 提供 `/sbin/init`、shell、库、配置和应用。Kernel 能运行但找不到或无法挂载 rootfs，仍然会启动失败。

### 14.7 Buildroot 是什么？

Buildroot 通过 Kconfig/Makefile 选择包、交叉编译用户空间组件，最终生成精简 rootfs。它适合固件式系统，不等同于在板端用 `apt` 维护的通用 Ubuntu/Debian 系统。

### 14.8 静态库和动态库有什么区别？

静态库 `.a` 在链接时将所需代码复制进可执行文件，部署简单但文件大、升级库时需重新链接。动态库 `.so` 在运行时加载，可共享代码，但需满足 ABI、版本和搜索路径。

### 14.9 什么是 ABI？

ABI 是二进制层面的约定，包括调用约定、数据类型布局、系统调用和符号规则。架构相同不代表 ABI 必然兼容。

### 14.10 什么是 Kernel module？

`.ko` 是可在运行时加载的内核目标文件。它必须与目标 Kernel 的版本、配置和符号兼容，不能把其他内核的 `.ko` 随意复制进 rootfs。

### 14.11 Loader 和 Maskrom 有什么区别？

Loader 模式中，板卡已运行可与主机烧录工具通信的加载器。Maskrom 是 SoC BootROM 的更底层恢复模式，常用于存储无有效 Loader 或普通启动已损坏的情况。

### 14.12 为什么用 SHA256？

SHA256 可将大文件映射为固定长度摘要。任意一个字节变化都会使校验值变化，因此可用来确认 SDK 压缩包和固件是否与发布记录完全一致。它不会证明文件功能正确，也不替代数字签名的身份验证。

### 14.13 为什么不能只看编译成功？

编译成功只证明源码和工具链在当前条件下生成了产物。它不证明分区打包正确、设备树匹配实际硬件、驱动可用、固件可烧录或系统可稳定运行。

### 14.14 为什么先验证商家板再移植？

这是建立可信对照组。若原始 SDK 在它对应的商家板上都无法编译或启动，后续 OmniEgo 底板上的错误就无法明确归因于基础 SDK 还是板级移植。

## 15. 本阶段完成标准

```text
[ ] Python 2.7.18 和必要主机依赖已配置
[ ] mlk_rk03_rk3576_defconfig 选择正确
[ ] U-Boot、Kernel、Buildroot、Recovery 全部编译成功
[ ] output/firmware/update.img 生成
[ ] update.img SHA256 已记录
[ ] 商家原始镜像和 Maskrom 恢复方法已保留
[ ] 自编译 update.img 已烧录到对应商家开发板
[ ] 完整串口启动日志已保存
[ ] 启动、eMMC、rootfs、USB/网络等基本功能已验证
[ ] 编译提交 ID、固件 SHA256、板卡版本和结果已记录
```

只有完成上述基线，才建议创建 `board/minimal-boot` 分支并正式开始 OmniEgo 底板移植。
