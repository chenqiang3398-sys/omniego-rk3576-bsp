# OmniEgo RK3576 GitHub 版本管理标准教程

## 1. 文档目标

本文定义 OmniEgo RK3576 BSP 的标准版本管理方法，适用于以下开发环境：

```text
基础 SDK：/home/magine/uisrc/mlk-sdk-3576-v1.1.0
基础压缩包：/home/magine/uisrc/mlk-sdk-3576-v1.1.0.tar.gz
BSP 仓库：/home/magine/uisrc/omniego-rk3576-bsp
GitHub 账号：chenqiang3398-sys
GitHub 仓库：omniego-rk3576-bsp
远程地址：git@github.com:chenqiang3398-sys/omniego-rk3576-bsp.git
```

最终目标是让任何开发者都能通过“同一份基础 SDK + GitHub 中的 BSP 覆盖层”重现相同的源码和固件：

```text
原始 MLK/Rockchip SDK（只读基线）
                  +
omniego-rk3576-bsp（GitHub 管理的定制内容）
                  |
                  v
可构建、可测试、可追溯的 OmniEgo 完整工程
```

## 2. 为什么采用覆盖层仓库

### 2.1 不直接提交完整 SDK

当前 SDK 包含内核、Buildroot、Debian、Yocto、RTOS、交叉编译器、GPU/NPU 二进制和大量构建产物，整体规模超过普通 Git 单仓库适合承载的范围。其中包括：

```text
debian/linaro-rootfs.img                         约 4.4 GiB
debian/linaro-bookworm-*.tar.gz                  约 664 MiB
prebuilts/.../aarch64-none-elf-gdb               约 180 MiB
tools/linux/PinDebug/*.tar                       约 171 MiB
buildroot/output/                                大量编译产物
external/                                        约 6 GiB
```

GitHub 普通 Git 不接受超过 100 MiB 的单文件。即使使用 Git LFS，把整套 SDK 上传后也会产生很高的存储、下载和历史版本成本。

因此，GitHub 仓库只管理本项目真正拥有和修改的内容：

- OmniEgo/MLK 板级 defconfig；
- DTS/DTSI 和设备树 Makefile；
- 内核配置或内核补丁；
- Buildroot 配置、overlay 和自定义 package；
- 项目应用、测试源码和脚本；
- 移植说明、构建说明和验证记录；
- 基础 SDK、固件和发布产物的 SHA256；
- 后续确实需要维护的板级驱动。

### 2.2 这样做的工程收益

| 目标 | 为什么这样做 |
|---|---|
| 可追溯 | 每个板级修改都有提交、作者、时间和原因 |
| 可复现 | 基础 SDK 版本和 SHA256 固定，避免同名 SDK 内容不同 |
| 可回退 | 出现启动故障时可回退到上一个已验证标签 |
| 易审查 | GitHub 中只出现相关改动，不被十几 GiB 厂商代码淹没 |
| 易协作 | 新开发者只需取得基础 SDK，再应用覆盖层 |
| 控制风险 | 构建产物、私钥和厂商二进制不会误入 Git 历史 |
| 尊重授权 | 仓库保持私有，降低未经授权公开分发厂商内容的风险 |

## 3. 总体管理原则

1. 原始 SDK 压缩包永久保存，不修改、不覆盖。
2. 每次开发都从压缩包解出的工作副本开始，不直接修改压缩包。
3. GitHub 仓库是 OmniEgo 定制内容的唯一版本源。
4. `main` 分支只保存已经构建并完成相应硬件验证的状态。
5. 每个功能使用独立分支，通过 Pull Request 合并到 `main`。
6. 一个提交只完成一类逻辑修改，避免 DTS、驱动、rootfs 裁剪混在一起。
7. `update.img`、`rootfs.img`、工具链和 SDK 压缩包不进入 Git。
8. Secure Boot 私钥、Token、产品密码和设备密钥绝不进入 Git。
9. 每个可启动里程碑都创建带说明的 Git 标签。
10. 发布固件必须记录源码提交、构建配置、SHA256 和验证结果。

## 4. 一次性准备

### 4.1 安装工具

```bash
sudo apt update
sudo apt install -y git git-lfs openssh-client rsync
```

原因：Git 用于版本管理，SSH 用于安全连接 GitHub，rsync 用于在 SDK 和覆盖层仓库之间同步相对路径。Git LFS 暂时不使用，但可为后续确有必要的大型 IQ/模型文件预留能力。

### 4.2 配置 Git 身份

```bash
git config --global user.name "Chen Qiang"
git config --global user.email "chenqiang3398@gmail.com"
git config --global init.defaultBranch main
```

原因：姓名和邮箱会写入每一次提交，用于追踪修改责任。邮箱应当是 GitHub 账号已验证的邮箱，或者 GitHub 提供的 no-reply 邮箱。

检查配置：

```bash
git config --global --list
```

### 4.3 配置 GitHub SSH

```bash
ssh-keygen -t ed25519 -C "chenqiang3398@gmail.com"
cat ~/.ssh/id_ed25519.pub
```

保存路径提示时直接回车，使用默认的 `~/.ssh/id_ed25519`。私钥密码建议设置；终端输入密码时不会显示字符。

把 `id_ed25519.pub` 的完整内容添加到：

```text
GitHub -> Settings -> SSH and GPG keys -> New SSH key
```

验证连接：

```bash
ssh -T git@github.com
```

以下信息代表成功，不是错误：

```text
Hi chenqiang3398-sys! You've successfully authenticated,
but GitHub does not provide shell access.
```

原因：GitHub 允许通过 SSH 执行 Git 操作，但不提供服务器 Shell 登录。

## 5. 创建 GitHub 私有仓库

在 GitHub 中选择 `New repository`，使用以下设置：

```text
Owner：chenqiang3398-sys
Repository name：omniego-rk3576-bsp
Visibility：Private
README：不勾选
.gitignore：不选择
License：不选择
```

原因：本地已经有需要提交的内容，GitHub 端保持空仓库可以避免首次推送时出现无关的 README 提交和历史冲突。仓库设为私有，是因为当前 SDK 包含厂商二进制、文档和第三方组件，公开分发权限需要另行确认。

## 6. 建立本地覆盖层仓库

### 6.1 定义路径

环境变量只在当前终端有效。每次打开新终端后，需要重新执行：

```bash
export SDK_ROOT=/home/magine/uisrc/mlk-sdk-3576-v1.1.0
export BSP_REPO=/home/magine/uisrc/omniego-rk3576-bsp
```

检查变量，避免空变量导致文件写入错误位置：

```bash
printf 'SDK_ROOT=%s\n' "$SDK_ROOT"
printf 'BSP_REPO=%s\n' "$BSP_REPO"
```

### 6.2 创建仓库目录

```bash
mkdir -p "$BSP_REPO"
```

本仓库必须和 SDK 并列，而不是放进 SDK 内部。这样可以避免 SDK 中几十个失效的嵌套 `.git` 被识别成子仓库，也不会误提交完整 SDK。

### 6.3 导入当前板级基线

```bash
cd "$SDK_ROOT"

rsync -aR \
  note/ \
  device/rockchip/.chips/rk3576/ \
  kernel-6.1/arch/arm64/boot/dts/rockchip/mlk-rk03-rk3576-linux.dts \
  kernel-6.1/arch/arm64/boot/dts/rockchip/rk3576-evb1.dtsi \
  kernel-6.1/arch/arm64/boot/dts/rockchip/Makefile \
  kernel-6.1/arch/arm64/boot/dts/rockchip/rk03/ \
  kernel-6.1/arch/arm64/configs/rockchip_linux_defconfig \
  buildroot/configs/rockchip_rk3576_defconfig \
  test/Makefile \
  test/key_control.c \
  test/led_control.c \
  test/rk3576-mlka-env.sh \
  "$BSP_REPO/"
```

`-R` 保留相对目录结构，因此仓库内文件可以直接覆盖回相同版本的 SDK。只列出允许管理的路径，可以防止 `rootfs.img`、Buildroot 输出和工具链被意外复制。

不要复制以下生成文件：

```text
test/key_control
test/led_control
kernel-6.1/boot.img
kernel-6.1/resource.img
buildroot/output/
debian/linaro-rootfs.img
```

## 7. 规范仓库结构

建议最终结构如下：

```text
omniego-rk3576-bsp/
├── BASE_SDK.md
├── README.md
├── .gitignore
├── manifests/
│   ├── base-sdk.sha256
│   └── releases/
├── note/
├── device/rockchip/.chips/rk3576/
├── kernel-6.1/
│   └── arch/arm64/...
├── buildroot/configs/
├── test/
└── scripts/
```

各模块职责：

| 模块 | 版本管理内容 | 不应存放 |
|---|---|---|
| `device/` | SDK defconfig、ITS、parameter、打包配置 | `output/firmware` |
| `kernel-6.1/` | DTS/DTSI、配置、板级驱动或补丁 | Image、DTB、模块产物 |
| `buildroot/` | defconfig、overlay、自定义 package | `output/`、`dl/` |
| `test/` | 测试源码、脚本、预期结果 | 已编译程序和日志 |
| `note/` | 移植设计、操作教程、验证记录 | 大型 PDF 和厂商全套文档 |
| `manifests/` | SDK/固件 SHA256、发布清单 | SDK 和固件本体 |
| `scripts/` | 覆盖、检查和构建辅助脚本 | 密码、Token、私钥 |

## 8. 建立忽略规则

在 `$BSP_REPO/.gitignore` 中配置：

```gitignore
# Build output
output/
build/
artifacts/
buildroot/output/
buildroot/dl/
debian/binary/

# Generated kernel files
*.o
*.ko
*.mod
*.cmd
*.dtb
*.dtbo
Module.symvers
modules.order

# Firmware and filesystem images
*.img
*.iso

# Local test binaries
/test/key_control
/test/led_control

# Logs and temporary files
*.log
*.tmp
*.swp

# Secrets and signing keys
.env
keys/
*.pem
*.key
```

原因：`.gitignore` 只防止尚未跟踪的文件被误提交。文件一旦进入 Git 历史，后来再添加忽略规则并不会自动删除历史中的副本，所以必须在第一次 `git add` 前检查好。

## 9. 固定基础 SDK 身份

### 9.1 编写 BASE_SDK.md

内容至少包括：

```markdown
# Base SDK

- SDK: MLK SDK RK3576 V1.1.0
- Base archive: mlk-sdk-3576-v1.1.0.tar.gz
- Rockchip release: rk3576_linux6.1_release_v1.1.0_20241220
- Kernel: Linux 6.1.99
- U-Boot: 2017.09 Rockchip
- Buildroot: 2024.02
- Yocto: 5.0.3
- Default target: mlk_rk03_rk3576_defconfig
- Base SDK storage: local read-only backup or company NAS
```

原因：目录名和压缩包名可能相同，但内容可能被重新打包或修改。版本说明提供人类可读信息，SHA256 提供机器可验证身份。

### 9.2 生成基础压缩包 SHA256

```bash
mkdir -p "$BSP_REPO/manifests"
cd /home/magine/uisrc
sha256sum mlk-sdk-3576-v1.1.0.tar.gz \
  > "$BSP_REPO/manifests/base-sdk.sha256"
```

验证：

```bash
cd /home/magine/uisrc
sha256sum -c "$BSP_REPO/manifests/base-sdk.sha256"
```

预期结果：

```text
mlk-sdk-3576-v1.1.0.tar.gz: OK
```

只提交几十字节的校验文件，不提交 SDK 压缩包。以后任何人得到基础包后，都可以判断它是不是完全相同的文件。

## 10. 第一次 Git 提交

### 10.1 初始化或检查仓库

```bash
cd "$BSP_REPO"
git status
```

如果提示 `not a git repository`，再执行：

```bash
git init -b main
```

如果显示 `Reinitialized existing Git repository`，代表该目录以前已经初始化，不是错误。不要反复初始化，也不要删除 `.git`。

### 10.2 提交前检查

```bash
git status --short
git add .
git diff --cached --stat
git diff --cached --check
```

重点检查暂存区中不能出现：

```text
*.img
*.dtb
*.o
*.ko
buildroot/output/
debian/linaro-rootfs.img
prebuilts/
external/
```

`git diff --cached --check` 用于发现行尾空格等基础格式问题。`git diff --cached --stat` 用于在提交前确认文件范围和规模是否符合预期。

提交：

```bash
git commit -m "chore: import RK3576 board customization baseline"
```

如果显示 `nothing to commit, working tree clean`，表示当前内容已经提交或没有变化。使用下面的命令确认历史：

```bash
git log --oneline --decorate -5
```

## 11. 关联 GitHub 并推送

当前项目使用的准确地址是：

```text
git@github.com:chenqiang3398-sys/omniego-rk3576-bsp.git
```

首次添加：

```bash
git remote add origin git@github.com:chenqiang3398-sys/omniego-rk3576-bsp.git
```

注意：命令中不能输入 `<chenqiang3398-sys>`。尖括号在教程里通常表示占位符，但在 Bash 中 `<` 是输入重定向符，会产生 `No such file or directory`。

检查远程地址：

```bash
git remote -v
```

如果 `origin` 已存在但地址错误：

```bash
git remote set-url origin git@github.com:chenqiang3398-sys/omniego-rk3576-bsp.git
```

推送：

```bash
git push -u origin main
```

`-u` 会建立本地 `main` 与远程 `origin/main` 的跟踪关系，之后可以直接使用 `git push` 和 `git pull`。

## 12. 创建基线标签

确认 `main` 已推送后执行：

```bash
git tag -a baseline/sdk-v1.1.0 \
  -m "Initial MLK RK3576 SDK customization baseline"
git push origin baseline/sdk-v1.1.0
```

分支用于持续开发，标签用于标记不可移动的里程碑。基线标签代表当前导入状态，不代表 OmniEgo 底板已经完成硬件验证。

建议标签体系：

```text
baseline/sdk-v1.1.0              初始 SDK 定制基线
bsp/v0.1.0-minimal-boot          最小系统启动验证通过
bsp/v0.2.0-base-peripherals      基础底板外设验证通过
bsp/v0.3.0-display-audio         显示和音频验证通过
bsp/v0.4.0-camera-single         单路相机验证通过
bsp/v0.5.0-camera-multi          四路相机验证通过
release/v1.0.0                   首个产品发布版本
```

## 13. 标准分支开发流程

本项目采用简化的 GitHub Flow，不建立长期 `develop` 分支：

```text
main
  +-- board/minimal-boot
  +-- feature/tf-card
  +-- feature/usb-host
  +-- feature/typec
  +-- feature/display
  +-- feature/audio
  +-- feature/camera0
  +-- feature/multi-camera
  +-- feature/camera-trigger
  +-- feature/charger
  +-- fix/<问题名称>
  +-- docs/<文档名称>
```

原因：当前开发者数量有限，使用功能分支和 Pull Request 已能提供隔离、审查和回退能力；额外的长期 `develop` 分支会增加同步成本。

开始新任务：

```bash
cd "$BSP_REPO"
git switch main
git pull --ff-only
git switch -c board/minimal-boot
```

`--ff-only` 防止拉取时自动生成意外的合并提交。

## 14. SDK 与 BSP 仓库之间的同步

### 14.1 开发方向

硬件构建必须在完整 SDK 中进行，因此标准方向是：

```text
在 SDK 中修改和编译
        |
        v
将允许管理的源码同步到 BSP_REPO
        |
        v
检查差异、提交、推送
```

### 14.2 从 SDK 导出修改

修改完成后重新执行受控 rsync：

```bash
cd "$SDK_ROOT"

rsync -aR \
  note/ \
  device/rockchip/.chips/rk3576/ \
  kernel-6.1/arch/arm64/boot/dts/rockchip/mlk-rk03-rk3576-linux.dts \
  kernel-6.1/arch/arm64/boot/dts/rockchip/rk3576-evb1.dtsi \
  kernel-6.1/arch/arm64/boot/dts/rockchip/Makefile \
  kernel-6.1/arch/arm64/boot/dts/rockchip/rk03/ \
  kernel-6.1/arch/arm64/configs/rockchip_linux_defconfig \
  buildroot/configs/rockchip_rk3576_defconfig \
  test/Makefile \
  test/key_control.c \
  test/led_control.c \
  test/rk3576-mlka-env.sh \
  "$BSP_REPO/"
```

以后新增正式板级目录、驱动、Buildroot overlay 或应用时，要把对应路径加入受控列表。不要为了方便改成同步整个 SDK。

### 14.3 从仓库覆盖到一份干净 SDK

从 GitHub 克隆覆盖层后，按模块应用：

```bash
rsync -a "$BSP_REPO/device/" "$SDK_ROOT/device/"
rsync -a "$BSP_REPO/kernel-6.1/" "$SDK_ROOT/kernel-6.1/"
rsync -a "$BSP_REPO/buildroot/" "$SDK_ROOT/buildroot/"
rsync -a "$BSP_REPO/test/" "$SDK_ROOT/test/"
rsync -a "$BSP_REPO/note/" "$SDK_ROOT/note/"
```

应用覆盖层前，SDK 必须来自 `base-sdk.sha256` 对应的干净基础包。否则相同覆盖层应用到不同 SDK，可能产生难以定位的行为差异。

## 15. 日常提交规范

每次提交前执行：

```bash
cd "$BSP_REPO"
git status
git diff
git add <本次修改的明确路径>
git diff --cached
git diff --cached --check
git commit -m "<模块>: <简短动作说明>"
git push -u origin HEAD
```

命令中的 `<本次修改的明确路径>` 是占位说明，实际执行时不能保留尖括号。例如：

```bash
git add kernel-6.1/arch/arm64/boot/dts/rockchip/
git commit -m "dts: add OmniEgo minimal boot configuration"
```

推荐提交前缀：

| 前缀 | 用途 | 示例 |
|---|---|---|
| `dts:` | 设备树修改 | `dts: enable OmniEgo debug UART` |
| `kernel:` | 内核配置或驱动 | `kernel: enable PWM fan driver` |
| `buildroot:` | rootfs 配置 | `buildroot: add camera diagnostic tools` |
| `app:` | 应用代码 | `app: add camera trigger service` |
| `test:` | 测试代码 | `test: add TF card read-write test` |
| `docs:` | 文档 | `docs: document Type-C bring-up results` |
| `fix:` | 缺陷修复 | `fix: correct camera reset polarity` |
| `chore:` | 工程维护 | `chore: record base SDK checksum` |

一个提交应当能够独立解释和回退。例如“启用 TF 卡 DTS”和“删除 Chromium”应拆成两个提交。

## 16. Pull Request 和 main 分支规则

功能分支推送后，在 GitHub 创建 Pull Request。描述中至少填写：

```text
目的：为什么修改
修改范围：涉及哪些 DTS、配置或驱动
构建结果：使用哪个 defconfig，是否构建通过
硬件结果：在哪块板上验证，测试了什么
风险：可能影响哪些接口或复用引脚
回退方法：回退哪个提交或关闭哪个节点
```

建议在 GitHub `Settings -> Rules -> Rulesets` 中保护 `main`：

- 禁止 force push；
- 禁止删除 `main`；
- 要求通过 Pull Request 合并；
- 至少完成一次差异自检；
- 合并前确认没有固件、密钥和构建产物。

原因：`main` 是可复现和可回退的稳定入口，不应直接堆叠未经验证的实验修改。

## 17. 固件和发布管理

### 17.1 固件不进入 Git

以下文件存放在 NAS、对象存储或受控发布目录：

```text
MiniLoaderAll.bin
uboot.img
boot.img
recovery.img
rootfs.img
update.img
完整 SDK 压缩包
```

GitHub 中只保存发布清单。例如 `manifests/releases/v0.1.0.md`：

```markdown
# OmniEgo BSP v0.1.0

- Git commit: <完整提交 ID>
- Git tag: bsp/v0.1.0-minimal-boot
- SDK checksum: manifests/base-sdk.sha256
- Defconfig: mlk_rk03_rk3576_defconfig
- Build date: YYYY-MM-DD
- Firmware storage: NAS 路径或制品地址
- update.img SHA256: <校验值>
- Board revision: OmniEgo Rev.X
- Result: UART/eMMC/USB OTG verified
```

生成固件校验值：

```bash
sha256sum "$SDK_ROOT/output/firmware/update.img"
```

原因：Git 负责管理源码历史，制品存储负责管理大型固件。二者通过提交 ID、标签和 SHA256 建立确定关系。

### 17.2 Git LFS 的使用边界

只有确实属于项目源码资产、无法通过基础 SDK 或构建过程恢复的二进制，才考虑 Git LFS，例如：

- 自研 Camera IQ 文件；
- 必须随项目维护的 RKNN 模型；
- 板级 MCU 固件；
- 厂商许可允许上传的屏幕初始化固件。

按明确目录跟踪，不要全局跟踪整个 `external/`：

```bash
git lfs install
git lfs track "assets/models/**"
git lfs track "firmware/board/**"
git add .gitattributes
git commit -m "chore: configure LFS for board assets"
```

LFS 不是无限空间。每次更新大型文件都会产生新的存储对象，因此 rootfs、工具链和完整 SDK 仍然不能放入 LFS。

## 18. 安全和授权规则

禁止提交：

```text
GitHub Personal Access Token
SSH 私钥 ~/.ssh/id_ed25519
Secure Boot/AVB/FIT/RSA 私钥
Wi-Fi、服务器和产品账号密码
设备唯一密钥、证书和量产密钥
包含客户身份或硬件机密的未授权资料
```

如果敏感信息已经提交，仅仅删除工作区文件不够，因为历史提交中仍有副本。应立即停止推送、轮换泄漏的密钥，再使用专用历史清理工具处理。

## 19. 从零复现流程

这是判断版本管理方案是否合格的最终流程。

### 19.1 建立独立复现目录

```bash
export REPRO_ROOT=/home/magine/uisrc/omniego-reproduce
mkdir -p "$REPRO_ROOT"
find "$REPRO_ROOT" -mindepth 1 -maxdepth 1 -print
```

第一次复现时，`find` 不应输出任何内容。如果有输出，请改用另一个空目录，不要直接删除或覆盖现有工作副本。

原因：复现验证必须与日常开发目录隔离，否则遗留文件可能让一个本来不完整的覆盖层“看起来能构建”。

### 19.2 克隆 BSP 仓库

```bash
git clone git@github.com:chenqiang3398-sys/omniego-rk3576-bsp.git \
  "$REPRO_ROOT/omniego-rk3576-bsp"
```

### 19.3 验证并解压基础 SDK

```bash
cd /home/magine/uisrc
sha256sum -c \
  "$REPRO_ROOT/omniego-rk3576-bsp/manifests/base-sdk.sha256"
tar -xf mlk-sdk-3576-v1.1.0.tar.gz -C "$REPRO_ROOT"
```

校验结果必须是 `mlk-sdk-3576-v1.1.0.tar.gz: OK`。因为清单记录的是文件名而不是某台机器的绝对路径，校验时需要在压缩包所在目录执行。只有校验通过才继续解压。

### 19.4 应用覆盖层

```bash
export SDK_ROOT="$REPRO_ROOT/mlk-sdk-3576-v1.1.0"
export BSP_REPO="$REPRO_ROOT/omniego-rk3576-bsp"

rsync -a "$BSP_REPO/device/" "$SDK_ROOT/device/"
rsync -a "$BSP_REPO/kernel-6.1/" "$SDK_ROOT/kernel-6.1/"
rsync -a "$BSP_REPO/buildroot/" "$SDK_ROOT/buildroot/"
rsync -a "$BSP_REPO/test/" "$SDK_ROOT/test/"
rsync -a "$BSP_REPO/note/" "$SDK_ROOT/note/"
```

### 19.5 配置和构建

```bash
cd "$SDK_ROOT"
make mlk_rk03_rk3576_defconfig
make
```

验收输出至少包括：

```text
output/firmware/MiniLoaderAll.bin
output/firmware/uboot.img
output/firmware/boot.img
output/firmware/recovery.img
output/firmware/rootfs.img
output/firmware/update.img
```

当前主机若缺少构建依赖，应先按 Rockchip SDK 文档安装依赖。版本管理成功不等于固件已经构建或硬件验证成功，这三个状态需要分别记录。

## 20. 常见错误排查

### 20.1 `bash: chenqiang3398-sys: No such file or directory`

错误写法：

```bash
git remote add origin git@github.com:<chenqiang3398-sys>/omniego-rk3576-bsp.git
```

正确写法：

```bash
git remote add origin git@github.com:chenqiang3398-sys/omniego-rk3576-bsp.git
```

原因：尖括号是文档占位符，不是命令内容；Bash 把 `<` 解释为输入重定向。

### 20.2 `origin does not appear to be a git repository`

检查：

```bash
git remote -v
```

没有 `origin` 时添加，地址错误时使用 `git remote set-url` 修正。

### 20.3 `warning: re-init`

表示当前目录已经有 `.git`，重复执行了 `git init`。通常不是故障。使用 `git status` 和 `git log` 检查当前仓库，不要删除 `.git` 重来。

### 20.4 `nothing to commit, working tree clean`

表示没有新的未提交修改。检查：

```bash
git status
git log --oneline --decorate -5
```

### 20.5 `sha256sum: No such file or directory`

`/path/to/file` 是占位路径。先使用 `find` 定位实际压缩包，再替换成真实路径。当前实际基础包是：

```text
/home/magine/uisrc/mlk-sdk-3576-v1.1.0.tar.gz
```

### 20.6 GitHub 拒绝大文件

先检查暂存区：

```bash
git diff --cached --stat
find . -type f -size +90M -print
```

不要立刻用 LFS 掩盖问题。先判断该文件是不是构建产物、基础 SDK 内容或可以从其他来源恢复；这三类文件应从仓库中排除。

## 21. 每日工作检查表

开始开发前：

- 当前分支是否正确；
- `main` 是否已 `git pull --ff-only`；
- 是否为本次任务创建独立分支；
- 基础 SDK 是否与 SHA256 匹配；
- 是否保留已知可启动固件。

提交前：

- `git status` 中是否只有预期文件；
- 是否误加入镜像、对象文件、日志和密钥；
- 是否查看了完整 `git diff`；
- 提交是否只包含一个逻辑修改；
- 提交说明是否能解释修改目的。

合并前：

- defconfig 是否可生成；
- 对应模块是否构建通过；
- 硬件验证是否完成并记录；
- 是否说明引脚复用、供电和兼容性风险；
- 是否具备明确回退点。

发布前：

- `main` 是否处于干净状态；
- 是否创建版本标签；
- 是否记录完整提交 ID；
- 是否计算并记录固件 SHA256；
- 是否记录板卡版本、构建环境和测试结果；
- 是否将固件放入受控制品存储，而不是 Git。

## 22. 当前项目的下一步

完成仓库初始化后，建议按以下顺序推进：

1. 确认初始基线提交已推送到私有 GitHub 仓库。
2. 创建并推送 `baseline/sdk-v1.1.0` 标签。
3. 创建 `board/minimal-boot` 分支。
4. 建立真正的 OmniEgo 最小启动 DTS 和独立 defconfig。
5. 完成 UART、eMMC、USB OTG 的构建与硬件验证。
6. 合并 Pull Request，并创建 `bsp/v0.1.0-minimal-boot` 标签。
7. 再按 TF Card、USB Host、Type-C、显示、音频、单路相机、四路相机的顺序开发。

这套流程的核心不是“把文件上传到 GitHub”，而是建立以下闭环：

```text
明确基础版本
  -> 隔离功能开发
  -> 受控同步源码
  -> 审查提交内容
  -> 构建和硬件验证
  -> 标签固定里程碑
  -> 固件与源码建立校验关系
  -> 随时可以复现和回退
```

## 23. 官方参考

- GitHub SSH：https://docs.github.com/en/authentication/connecting-to-github-with-ssh
- 添加本地代码：https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github
- GitHub 大文件限制：https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github
- Git LFS：https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-git-large-file-storage
