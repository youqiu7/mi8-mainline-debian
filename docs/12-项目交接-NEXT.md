# 米8 移植 Debian —— 项目交接（NEXT）

> ⚠️ **本文已过时**。最新状态见 `16-项目交接-20261021-0941.md`（13 号也已归档）。
> 旧文写的"卡在 pivot_root"已解决：实际 `switch_root` 已成功、systemd 已接管，当前在排查"systemd 静默无串口输出"。
>
> **写给下一个会话（人或 AI）**：读完这一份就能接上，不需要重新摸索。
> 生成时间：2026-10-21 09:40
> 项目根：`F:\小米刷机\米8移植debian`

---

## 0. 一句话现状

**引导链已全线打通**（UEFI → 内核 → UFS → rootfs 挂载 → 串口），**只差 `pivot_root` 之后 `exec /sbin/init` 这一步**才进 Debian。
最后三个 bug 已定位并修复两个半，**第三个（`chdir(NEWROOT)` 在 pivot_root 之前）已改但尚未拿到实机验证**。

---

## 1. 目标与硬约束（用户需求，勿改）

| 项 | 需求 |
|---|---|
| 设备 | 小米 8 屏幕指纹版 **equuleus**（M1807E8A / SDM845），serial `225bd9ea` |
| 系统 | **Debian，当服务器用**（不装桌面、不要 GUI）|
| 联网 | **WiFi**：`OPPO A5-5G` / `<WIFI_PASSWORD>`，**不要 USB 网络（RNDIS）** |
| 账号 | `youqi` / `<WIFI_PASSWORD_ALT>`（uid 1000，sudo 组）；root 同密码 |
| USB | **固定 peripheral + CDC-ACM 串口**，`dr_mode="peripheral"`，**绝不切 host** |
| 保留 | Android 仍可启动（清 misc 即回 Android）|
| 屏幕 | **已换第三方屏**（显示屏/触摸/屏下指纹均非原厂）。驱动需从 Linux 读实际型号；**屏幕不通也不阻塞主线** |
| rootfs 位置 | `sda23`（原 `mindowswin`，59.7 GB，用户确认可格式化）|
| Linux 引导位置 | `recovery` 分区（放 EDK2 UEFI），普通开机仍进 Android |

---

## 2. 当前状态

| 环节 | 状态 | 证据 |
|---|---|---|
| EDK2 UEFI 引导 | ✅ | COM7 反复出现 |
| 内核 6.19.14 启动 | ✅ | `[init] alive 30s/60s/120s` |
| UFS 23 分区识别 | ✅ | `sda1..sda23` 全部正确 |
| USB CDC-ACM 串口 | ✅ | `r`/`d`/`m` 命令均有响应 |
| **rootfs 挂载 sda23** | ✅ | `/proc/mounts` 显示 `/dev/sda23 /newroot ext4 rw` |
| **/sbin/init 存在** | ✅ | 挂载后可见 |
| **pivot_root 切根** | ❌ **卡在这里** | 失败后退回诊断模式（只剩心跳）|
| `exec /sbin/init` | ⏸ | 未到达 |
| Android 可回 | ✅ | `r`（串口）或 `fastboot erase misc` |

**设备当前**：不在 USB 上（最后一次部署后 180 秒无 COM，可能没电或 panic）。**先插电、长按电源开机**。

---

## 3. 资产清单（路径 + md5，直接可用）

### 3.1 引导产物

```
C:\Users\duoya\AppData\Local\Temp\mi8flash\
  BOOTAA64-debian.efi   40,322,718  md5 06c21f8a  ← 最新（init v5 + 3 处修复 + m 诊断）
  BOOTAA64-ext4.efi     40,322,718  md5 eeb176a2  ← 已验证可启动（init v3 + EXT4）
  BOOTAA64-v3final.efi  39,720,606  md5 b0596ea6  ← 最保守基线（init v3，无 EXT4）
  boot-equuleus.img      6,660,096  md5 c7a9acfc  ← EDK2 UEFI（刷 recovery 用）
  rootfs-4g.img      4,294,967,296  md5 340125ab  ← Debian 13 rootfs
```

### 3.2 锚点（完整可回滚，4.3 GB）

```
F:\小米刷机\米8移植debian\03-备份\锚点-20261021-0515\
  01-boot/     UEFI + 3 个内核产物 + 原厂 recovery（69 MB）
  02-esp/      ESP 当前实际内容快照（BOOTAA64.EFI.running / dtb / bak-0020）
  03-rootfs/   rootfs-4g.img（4 GB）
  04-config/   kernel.config + key-options.txt
  05-scripts/  init_v3.c / init_v5.c + 9 个复现脚本
  md5-manifest.txt   19 个文件，全部 match
```

### 3.3 关键源码

```
F:\小米刷机\米8移植debian\04-实验\p3\init_v5.c     ← 当前在改的 init（switch_root 版）
F:\小米刷机\米8移植debian\04-实验\p1\init_v3.c     ← 已验证能跑的诊断版 init
F:\小米刷机\米8移植debian\04-实验\p3\53-build-debian-boot.sh   ← 一键构建（编 init + 编内核 + 拼 dtb）
```

### 3.4 文档

```
00-文档/10-成功状态与dtb陷阱.md   ← 复盘（dtb= 陷阱、fastboot boot 无效等）
00-文档/11-锚点与状态归档.md      ← 锚点详解 + 6 条坑 + 校验清单
00-文档/12-项目交接-NEXT.md       ← 本文件
02-工具/55-verify-before-v5.sh    ← 动 init 前的 21 项校验脚本
```

---

## 4. 引导链（已验证）

```
音量上+电源
  → ABL
  → recovery 分区（= boot-equuleus.img，EDK2 UEFI）
  → UEFI 读 ESP
  → EFI/Boot/BOOTAA64.EFI（= Image + 尾部 appended dtb）
  → 内核 6.19.14 启动（**cmdline 绝对不能有 dtb=**）
  → dwc3 probe → CDC-ACM 串口 COMx
  → init（内建在 Image 的 initramfs 里）
       ├─ 挂 proc/sys/dev
       ├─ 探测挂 sda23（ext4，读写）→ 成功则保留挂载
       ├─ 配 gadget（串口 + 可选 UMS 暴露 sda22=ESP）
       ├─ try_switch_root()
       │    ├─ 检查 /newroot/sbin/init（已有则复用挂载）
       │    ├─ 移动 /proc /sys /dev 进新根（MS_MOVE）
       │    ├─ chdir("/")   ← 必须在 old root！
       │    ├─ pivot_root(/newroot, /newroot/.oldroot)
       │    ├─ chdir("/") + umount2("/.oldroot", MNT_DETACH)
       │    └─ exec /sbin/init
       └─ 失败 → 诊断模式（心跳 + r/d/m 命令）
```

---

## 5. 当前卡点与已修 bug

### 5.1 已修复的三个 bug（都表现为 EBUSY 或黑屏）

| # | Bug | 修法 | 状态 |
|---|---|---|---|
| 1 | 探测挂载成功后 `umount(NEWROOT)` 失败 → `/newroot` 残留挂载 | 探测成功后**保留挂载**，switch_root 复用 | ✅ 已修 |
| 2 | `sda23` 被配成 UMS `lun.1` → 自我占用 | **不再**把 ROOT_DEV 配成 lun.1 | ✅ 已修 |
| 3 | `chdir(NEWROOT)` 在 `pivot_root` **之前** | 改为 `chdir("/")` | ✅ 已改，**未验证** |

`pivot_root(2)` 手册原文：
> The current root **and current working directory** of the calling process must be on the **old root** filesystem, not on the new root filesystem.

### 5.2 待验证

最新内核 `BOOTAA64-debian.efi`（md5 `06c21f8a`）已写入 ESP，但两次部署都因设备无响应而未拿到 `m` 输出。

**下一步必须做的验证**：设备起来后串口发 `m`，看：
```
[m] 上次 switch_root: pivot_root 失败 errno=22 (...)
[m] /newroot/.oldroot 存在: 1
[m] /newroot/sbin/init 存在: 1
```
- 若 `switch_root` 那行显示"成功或未执行" → 说明已切根，看串口有没有 systemd 日志
- 若显示 `pivot_root 失败 errno=X` → 按 errno 继续修（EINVAL=参数/前提，EBUSY=挂载问题）

---

## 6. 下一步（可直接执行）

### 步骤 0：设备恢复

```bash
# 插充电器 20 分钟（原装线，别接电脑 USB）
# 然后长按电源 15 秒 → 再按电源开机
# 确认状态：
PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
cd "$PT"
./adb.exe devices          # 期望 225bd9ea device
./fastboot.exe devices     # 或在这
```

### 步骤 1：写 ESP（若在 Android）

```bash
cd "F:/小米刷机/米8移植debian/02-工具"
bash 56-deploy-debian.sh      # 自动 push + md5 校验 + UEFI 引导 + 抓日志
```

### 步骤 2：拿诊断（UEFI 起来后）

```bash
# 串口 COM7，发 m
powershell -NoProfile -ExecutionPolicy Bypass -Command "
\$sp = New-Object System.IO.Ports.SerialPort COM7,115200,'None',8,'One'
\$sp.DtrEnable=\$true; \$sp.RtsEnable=\$true; \$sp.ReadTimeout=600
\$sp.Open(); Start-Sleep -Milliseconds 500
\$sp.Write('m' + [char]13)
\$end=(Get-Date).AddSeconds(18); \$buf=New-Object char[] 8192
while((Get-Date) -lt \$end){ try{ \$n=\$sp.Read(\$buf,0,\$buf.Length); if(\$n -gt 0){ Write-Host -NoNewline (-join \$buf[0..(\$n-1)]) } }catch{} }
\$sp.Close()"
```

### 步骤 3：按诊断结果处理

| 诊断结果 | 动作 |
|---|---|
| `switch_root: (成功或未执行)` + systemd 日志 | ✅ **Debian 起来了**，用 `youqi`/`<WIFI_PASSWORD_ALT>` 串口登录 |
| `pivot_root 失败 errno=22 (EINVAL)` | 检查 `.oldroot` 是否创建、cwd 是否在 old root |
| `pivot_root 失败 errno=16 (EBUSY)` | 检查是否有残留挂载（`/proc/mounts`）|
| 仍只有心跳无 `m` 响应 | 内核起、init 卡在别处，查 `dmesg`（pstore）|
| 无 COM | 内核 panic，回滚到 `BOOTAA64-ext4.efi`（已验证）|

---

## 7. 关键教训（别再踩）

| # | 教训 |
|---|---|
| 1 | **cmdline 里绝不能有 `dtb=`**。UEFI 提供的 DTB 是动态修补过的；用 ESP 的静态 dtb 替换会让内核 early boot 死掉。接受 `DT model` 显示 `Xiaomi Mi MIX 2S`。 |
| 2 | **`fastboot boot <内核 boot.img>` 在本机从不成功**。只有 UEFI 路径能引导内核。别再用它测内核。 |
| 3 | **UMS 写入不可信**。`cp` 到 `E:` 后立即 md5 会通过（读 Windows 缓存）。必须用 **adb + 设备端 md5**。 |
| 4 | **dtb 生成必须验证 `reserved-memory` = 23**。cpp 漏 `-I scripts/dtc/include-prefixes` 或 dtc 漏 `-@` 会静默丢节点 → 内核覆盖保留内存 → 全黑。 |
| 5 | **回滚必须比对 md5**。同样大小（39,716,510）对应两份不同内容（init v3 `3e4ef13c` / init v4 `fa316ed2`）。 |
| 6 | **`pivot_root` 前 cwd 必须在 old root**。`chdir(newroot)` 之后再调必失败。 |
| 7 | **不要把要 switch_root 的分区同时配成 UMS lun**。自我占用 → EBUSY。 |
| 8 | **路径三套**：Windows git-bash 用 `/e/`，WSL 用 `/mnt/e/`（但 UMS 盘 WSL 看不到），传变量给 WSL 必须写成 `.sh` 文件。 |
| 9 | **串口句柄会泄漏**。COM 打不开时用 `Disable-PnpDevice` / `Enable-PnpDevice` 重置该设备。 |

---

## 8. 环境信息

| 项 | 值 |
|---|---|
| 设备 serial | `225bd9ea` |
| adb/fastboot | `F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools` |
| 内核源码/构建 | WSL Debian：`/root/k619/linux-6.19.14` |
| 交叉编译器 | `aarch64-linux-gnu-gcc (Debian 14.2.0-19)` |
| initramfs root | `/root/k619/p1-initramfs/root`（init 编译后放这里）|
| 串口 | COM7（USB CDC-ACM，115200）|
| UMS | ESP 暴露为 `E:` 盘（只读用，写入不可信）|
| 分区 | sda22=ESP(300MB) / sda23=rootfs(59.7GB) / sda21=userdata |

### 常用命令

```bash
# 构建 Debian 引导镜像（编 init v5 + 编内核 + 拼 dtb）
wsl.exe -d Debian -u root -- bash "/mnt/f/小米刷机/米8移植debian/04-实验/p3/53-build-debian-boot.sh"

# 部署（写 ESP + UEFI 引导）
cd "F:/小米刷机/米8移植debian/02-工具" && bash 56-deploy-debian.sh

# 动 init 前校验（21 项）
wsl.exe -d Debian -u root -- bash "/mnt/f/小米刷机/米8移植debian/02-工具/55-verify-before-v5.sh"

# 回滚到已验证能启动的版本
# 写 ESP 用 BOOTAA64-ext4.efi（md5 eeb176a2）
```

---

## 9. 后续路线（pivot_root 通了之后）

| 阶段 | 内容 |
|---|---|
| P4-A | 串口 login 验证（youqi/<WIFI_PASSWORD_ALT>）|
| P4-B | `first-boot.sh` 自动执行：对时 → resize2fs 到 59GB → 起 WiFi |
| P4-C | WiFi 验证：`ip link` 出 wlan0 → 连 OPPO A5-5G |
| P4-D | 内核重新加回 WiFi 驱动（`ATH10K_SNOC=y` + Kconfig 补丁，见 `00-文档/09-WiFi与服务器化实施.md`）|
| P5 | 屏幕/触摸（第三方屏，需从 Linux 读 DSI/I2C 实际型号；**可选，不阻塞服务器用途**）|

**注意**：WiFi 驱动之前加过（ath10k_snoc 内建），但因为 `dtb=` 陷阱被误判为"驱动问题"而回退。等系统稳定后再单独加，一次只改一个变量。
