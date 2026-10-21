# 成功状态与 dtb= 陷阱（2026-10-21 04:37）

## 一、已验证可启动的配置（唯一可靠基线）

**文件**：`C:\Users\duoya\AppData\Local\Temp\mi8flash\BOOTAA64-v3final.efi`
**大小**：39,720,606 B
**md5**：`b0596ea6759dc614abfa3184f58e1d5d`

组成：

```
Image  39,582,208 B   （init_v3.c 内建 initramfs，EXT4 关闭，ATH10K_SNOC 关闭）
dtb       138,398 B   （appended 在 Image 尾部，reserved-memory=23，wifi disabled）
cmdline             console=tty0 console=ttyGS0 earlycon=qcom_geni ignore_loglevel
                    loglevel=8 fbcon=map:0 acpi=off
                    ← 关键：没有 dtb=
```

引导链：

```
音量上+电源 → ABL → recovery 分区(boot-equuleus.img = EDK2 UEFI)
→ UEFI 读 ESP → EFI/Boot/BOOTAA64.EFI（上面的文件）
→ 内核启动 → dwc3 probe → COM7 出现 → [init] alive 30s/60s/120s
→ UFS 23 分区识别 → UMS 暴露 ESP 为 E: 盘
```

**实测证据（2026-10-21 01:12）**：

```
COM7 在 T+20s 出现
d 命令有响应（串口双向）
sda 120,152,064 块；sda22=307,204(ESP)；sda23=62,607,352(59.7GB)
PC 侧出现 Disk 1 (Linux File-Stor Gadget, 314,576,896 B) + E: 盘
```

## 二、dtb= 陷阱 —— 今晚最大的坑

**结论：cmdline 里的 `dtb=/equuleus.dtb` 会让内核 panic。**

原理解释：

1. 23:43 成功那次，cmdline **没有** `dtb=`，内核用的是 **UEFI 自己提供的 polaris DTB**
   （所以 `/proc/device-tree/model` 显示 `Xiaomi Mi MIX 2S`）
2. 我发现 DT model 不对（应该是 equuleus），于是在 cmdline 加了 `dtb=/equuleus.dtb`，
   让内核改从 **ESP 根目录**加载我们编译的 dtb（`CONFIG_EFI_ARMSTUB_DTB_LOADER` 支持）
3. 这个改动**之后每一次启动都全黑、无 USB、无 COM**
4. 即使 dtb 本身是完整的（138,570 / reserved-memory=23，节点结构与旧版逐个对齐），
   内核仍然在读到它之后立刻 panic

**为什么这条路不通（推断）**：

- UEFI 提供的 DTB 是**由 UEFI 固件在启动时动态修补过的**（补了 chosen/framebuffer/
  reserved-memory 的实际运行地址），而 ESP 里那份是**静态编译产物**，缺少 UEFI
  运行时的修补
- 内核 `efi_load_dtb()` 从 ESP 读到静态 dtb 后，直接用它替换了 UEFI 修补过的版本，
  于是丢失了 UEFI 的运行时信息 → 早期 panic

**因此**：

- ✅ **要用 UEFI 的 DTB**（不改 `dtb=`），接受 `DT model` 显示 polaris
- ❌ 不要试图用 `dtb=` 换成自己的 dtb，除非同时接管 UEFI 的 DTB 构建

**代价**：`DT model` 会显示 `Xiaomi Mi MIX 2S`，equuleus 特有的面板/触摸/电池节点可能不对。
但**服务器用途下这不影响主线**（串口、UFS、网络才是关键）。

## 三、今晚的失败链复盘

| 时间 | 我做了什么 | 结果 | 为什么 |
|---|---|---|---|
| 23:43 | UEFI + ESP 里的 init v3 内核（无 dtb=）| ✅ COM 出现 | 基线 |
| 23:47 | 加 `dtb=/equuleus.dtb` | ❌ 全黑 | 破坏 UEFI 的 DTB |
| 23:55~00:02 | 经 UMS 写 ESP 更新内核 | ❌ 从未生效 | Windows 对 removable 的写缓存 |
| 00:13 | auto-p3 自动 boot UEFI | ❌ 看到 GRUB | ESP 里还是旧东西 |
| 00:20 | adb 写 ESP（41MB 新内核，含 dtb=）| ❌ 无 COM | dtb= 陷阱 |
| 00:26 | 回退 Kconfig 重编 | ❌ 无 COM | 用的 dtb 本身还缺 reserved-memory |
| 00:32 | 修 dtb（138,570 完整）| ❌ 无 COM | 仍然带 dtb= |
| 00:39 | wifioff 测试 | ❌ 无 COM | 用坏 dtb（101,019）|
| 00:47~00:55 | 尝试恢复"基线" | ❌ 无 COM | **恢复的是 v4 版本，不是 v3** |
| 01:05 | v3 复刻（但仍带 dtb=）| ❌ 黑底白字 | 复刻不完整，漏了去掉 dtb= |
| 01:11 | **v3final（去掉 dtb=）** | ✅ **COM 出现** | 完全对齐 23:43 |

**核心教训**：

1. **"回滚到基线"必须核对 md5**，不能凭文件名/大小。39,716,510 这个大小对应两个不同内容
   （`3e4ef13c` = init v3，`fa316ed2` = init v4），我一直拿错的那个当基线
2. **UMS 写入不可信**，必须 adb + 设备端 md5
3. **`2>/dev/null` 会藏住 cpp/dtc 的错误**，dtb 少了 22 个 reserved-memory 节点完全看不出来
4. **一次只改一个变量**，且每次改动前先确认上一个基线状态

## 四、下一步（3 步，每步一个变量）

| 步骤 | 动作 | 验证 |
|---|---|---|
| 1 | 把 `rootfs-4g.img`（4GB ext4）写入 **sda23** | 需要 Android+adb（当前 init v3 的 UMS 只暴露 ESP）|
| 2 | 内核**只加 EXT4_FS=y**（init 仍是 v3，仍无 dtb=）| COM 仍出现 |
| 3 | init v3 → **init v5**（switch_root 到 sda23）| 串口出现 Debian login |

**第 1 步的实现方式**（二选一）：

- **A（推荐）**：设备回 Android → `adb push rootfs-4g.img` → `su -c dd if=... of=/dev/block/sda23`
- **B**：改用 init v4（双 LUN）暴露 sda23 → PC 写盘；但 v4 尚未验证能启动

## 五、当前设备状态

设备正跑着 v3final（Linux），COM7 可用，UMS 的 E: 盘可用。
要回 Android 需：串口发 `r`（init v3 的重启命令）→ 回 Android。
