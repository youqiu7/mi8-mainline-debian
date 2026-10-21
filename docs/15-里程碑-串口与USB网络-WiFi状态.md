# 15 — 里程碑：串口登录 + USB-NCM/SSH 通道 + WiFi 驱动就位（2026-10-21 05:10）

> 📌 **22:00 注**：本文"WiFi 卡点（QMI 缺 IPCRTR）"的判断**已被 17/19c/20 号修正、根因链已在 21/24/25 号彻底重写**（rmtfs→EFS→TZ 授权层）。串口/USB/锚点部分仍有效。当前见 `25-全面梳理与归档-2200`。

> 本文记录 13 号文档之后的实际进展，取代 `14` 的“待验证”部分。锚点见 `03-备份\锚点-20261021-0520\`。

---

## 一、已经打通并实测的链路

| 能力 | 证据 |
|---|---|
| **UEFI → 内核 → switch_root → systemd** | `Linux equuleus 6.19.14 #40 aarch64`，systemd 完整启动 |
| **串口 shell（ttyGS0）** | `root@equuleus:~#` 回显，`systemctl is-active ttygs0-console` = active |
| **根分区扩容** | `/dev/sda23 59G 495M 56G 1% /` |
| **USB CDC-NCM 链路** | Windows `UsbNcm Host Device` / Up / 426 Mbps；Linux `usb0 carrier=1` |
| **SSH over USB** | `ssh -i dagu_key root@169.254.1.1` → `uname -a` 正常 |
| **WiFi 驱动内建** | `ath10k_snoc` 绑定 `18800000.wifi`；DT `status=okay` + 5 路供电；固件在 initramfs + rootfs |
| **全链路自动化** | `02-工具/83-auto-cycle.sh`：任意状态 → Android → 写 ESP/rootfs → 引导 → 串口自检 |

### 1.1 串口的真正根因（已定性）

journal 硬证据：

```
00:04:56 systemd[1]: Expecting device dev-ttyGS0.device - /dev/ttyGS0...
00:12:26 systemd[1]: dev-ttyGS0.device: Job dev-ttyGS0.device/start timed out.
00:12:26 systemd[1]: Dependency failed for serial-getty@ttyGS0.service - Serial Getty on ttyGS0.
kernel: Warning: unable to open an initial console.
```

- `/dev` 是 initramfs 的 devtmpfs 经 `MS_MOVE` 搬进新根的，**udevd 没有对既有节点做 trigger** → `dev-ttyGS0.device` 不存在 → `serial-getty@` 依赖失败
- 同时内核 cmdline 里的 `console=ttyGS0` 在 gadget 出现前无法打开（`unable to open an initial console`），且会阻塞 printk

**修复**：
1. cmdline 去掉 `console=ttyGS0`，改用 `console=tty0` + `earlycon=qcom_geni`，并 `log_buf_len=4M`
2. 用 `ttygs0-console.service` 替代 `serial-getty@`（`ExecStart=/sbin/agetty --autologin root ... ttyGS0 vt100`，`Restart=always`，**不依赖 device unit**）
3. 去掉 `systemd.log_target=console`（否则 systemd 日志完全不进 journal）

### 1.2 USB 网络（不是 RNDIS）

- **Windows 11 25H2 已移除 RNDIS 驱动**（`ProblemCode 28`），必须用 CDC-NCM
- init v7 的 gadget：`acm.GS0 + ncm.usb0`（`sys/kernel/config/usb_gadget/g1`）
- gadget 接口（类型 `gadget`）**systemd-networkd 不接管**（`networkctl` 显示 `Network File: n/a`），所以用 oneshot 服务固定地址：

```
/etc/systemd/system/usb0-static.service
ExecStart=/bin/sh -c 'ip link set usb0 up; ip addr add 169.254.1.1/16 dev usb0; ip addr add 10.55.0.1/24 dev usb0'
```

- Windows 侧无需管理员权限：Windows 的 APIPA 地址 `169.254.x.x/16` 与 `169.254.1.1/16` 同网段，直接可 ping / ssh
- SSH 免密：`/root/.ssh/authorized_keys` 已写入 `dagu_key.pub`

**常用命令**：

```bash
ssh -i /c/Users/duoya/.ssh/dagu_key -o StrictHostKeyChecking=no root@169.254.1.1
```

---

## 二、WiFi：驱动就位，卡在 QMI 传输层

### 2.1 已完成

- `CONFIG_CFG80211=y / MAC80211=y / ATH10K=y / ATH10K_SNOC=y / QCOM_QMI_HELPERS=y / QCOM_RPROC_COMMON=y / RPMSG_QCOM_GLINK_SMEM=y`
- Kconfig 补丁：`QCOM_RPROC_COMMON` 由 `tristate` 改 `bool`；`ATH10K_SNOC` 由 `depends on ... || =n` 改 `select`
- DTS：`&wifi { status = "okay"; 5 路供电; }`（与上游 LG G7 WiFi 补丁逐字一致）
- 固件：`ath10k/WCN3990/hw1.0/{firmware-5.bin, wlanmdsp.mbn, board-2.bin}`，**同时放入 initramfs 和 rootfs**（probe 发生在 switch_root 之前）
- 结果：`ath10k_snoc` 驱动成功绑定 `18800000.wifi`，`bind_rc=0`，5 个 regulator supplier 全部解析

### 2.2 卡点

- `/sys/class/ieee80211/` **为空**（没有 wiphy），`/sys/class/net` 只有 `lo`、`usb0`
- dmesg/journal **没有任何 ath10k 日志** —— 因为 `ath10k_core_register()` 不在 probe 里，而在 **QMI 服务到达的回调**（`snoc.c:1369`）
- probe 只做 `ath10k_fw_init()` + `ath10k_qmi_init()`，成功后静默返回 0
- QMI 走 `sockaddr_qrtr` + `kernel_connect` → 需要 QRTR 传输层
- 现状：`/sys/bus/rpmsg/devices/` **为空**（没有 `IPCRTR` 通道），`CONFIG_QRTR_SMD=m`（无模块目录）
- 上游 `sdm845.dtsi` 的 wifi 节点没有 glink/smd 子节点；全树也无 wcss remoteproc

### 2.3 结论与下一步

WiFi 还差 **QMI 的 IPCRTR 传输通道**。深入核对后的硬结论：

- `ath10k_qmi_init()` 只做 `qmi_handle_init()` + `qmi_add_lookup(WLFW_SERVICE)`，**自己创建任何传输层都不做**
- QMI 走 QRTR，QRTR 的传输是 rpmsg 的 `IPCRTR` 通道（`net/qrtr/smd.c` 匹配 `{ "IPCRTR" }`）
- `IPCRTR` 通道只能来自 DT 的 `glink-edge`（`qcom,glink-channels = "IPCRTR"`）或 `smd-edge`
- **全树核对结果**：`arch/arm64/boot/dts/qcom/` 里除 ipq 系列与 sm8250-dagu 注释外，**没有任何平台提供 IPCRTR**；`sdm845.dtsi` 只有 `apss_shared: mailbox@17990000`，**没有 wcss smp2p，也没有 wcss remoteproc 节点**
- 上游 `sdm845.dtsi`（6.19）与 `sdm845-mainline/linux`（pmOS master）的 wifi 节点内容一致：只有 `compatible/reg/interrupts/iommus/memory-region/clocks`，无子节点
- **进一步核对 pmOS 实际使用的 `sdm845-6.11` tag**（他们 APKBUILD 里 `_tag=sdm845-6.11`，无本地补丁）：`sdm845.dtsi` 5971 行，wifi 节点与 6.19 **逐字相同**，全文件只有 adsp/cdsp 的 `apr_audio_svc`、`fastrpcglink-apps-dsp` 三个 glink 通道，**同样没有 IPCRTR、没有 smd-edge、没有 wcss_smp2p**
- 上游 LG G7 WiFi 补丁（patchew 20250928 v3 07/11）也只改 `&wifi` 的 5 路供电 + `qcom,snoc-host-cap-skip-quirk`——**与我们完全一致**

**因此纯 mainline 6.19 上 SDM845 的 WCN3990 QMI 缺一条传输边缘**，不是配置漏项，而是需要补 DT/驱动：

1. 给 `sdm845.dtsi` 增加 **wcss smp2p + glink-edge（`qcom,glink-channels = "IPCRTR"`）**，参考 `ipq6018.dtsi` 的 `q6v5_wcss` 写法（需要 wcss 侧 mbox 与 smp2p 中断）
2. 或移植 pmOS `sdm845-mainline/linux` 里 sdm845 WiFi 的 QMI 补丁（该树 LG G7 实测能出 `wlan0`，日志 `ath10k_snoc ... qmi chip_id 0x30214`）
3. pmOS wiki 对 beryllium（同 SDM845）的 WiFi 标注是 **Partial**，说明上游本身不完整

**工作量评估**：属于“一次小型 DT/驱动移植”，不是改个 config 能解决。建议先保留 SSH over USB 作为服务器网络通道，WiFi 作为独立任务排期。

---

## 三、锚点（2026-10-21 05:20）

**位置**：`03-备份\锚点-20261021-0520\`（43 文件 / 4.4 GB，`md5-manifest.txt` 全量校验通过）

```
01-boot/
  BOOTAA64-wifi2-00b17e15.efi     ← 【当前运行】init v7 + WiFi 驱动 + 固件在 initramfs
  BOOTAA64-wifi-5c977dce.efi      ← WiFi 驱动已编入，固件仅在 rootfs（无 wlan0）
  BOOTAA64-ncm-7989f352.efi       ← acm+ncm，无 WiFi
  BOOTAA64-rndis-98eea6b2.efi     ← acm+rndis（Win11 无驱动，留档）
  BOOTAA64-badcmdline-0c25619f.efi← 反例：console=ttyGS0 导致内核静默
  BOOTAA64-ueficmdline-deb0b27b.efi← 用 UEFI cmdline 的版本（能 switch_root，无串口）
  BOOTAA64-v3final.efi            ← 最保守基线
  boot-equuleus.img / recovery-原厂.img
02-esp/
  BOOTAA64.EFI.running            = wifi2
  equuleus-wifi.dtb               = 9242721c（wifi okay + 5 路供电）
03-rootfs/
  rootfs-4g-f6a1f11e.img          ← 干净镜像（entropy/getty/proof/固件/usb0 配置）
  runtime-incremental.tgz         ← 运行时增量（usb0-static.service、authorized_keys、proof.log、first-boot.log）
04-config/
  kernel.config / key-options.txt
05-scripts/
  init_v5/v6/v7.c、44–90 号全部脚本、com_probe.py、com_monitor.py
```

### 回滚方法

| 想回到 | 操作 |
|---|---|
| 串口可用 + USB 网络 + 无 WiFi 驱动 | 写 ESP：`BOOTAA64-ncm-7989f352.efi`（rootfs 不用动） |
| 当前状态（WiFi 驱动在，无 wlan0） | 写 ESP：`BOOTAA64-wifi2-00b17e15.efi` |
| 最保守能启动 | 写 ESP：`BOOTAA64-v3final.efi` |
| rootfs 回滚 | `dd if=rootfs-4g-f6a1f11e.img of=/dev/block/sda23 bs=4M conv=notrunc`（Android 下） |
| 回到 Android | `fastboot erase misc` 或串口 `reboot` |

写 ESP 一律：`adb push → su mount vfat /dev/block/sda22 → cp → md5 双校验`（脚本 `83-auto-cycle.sh --efi <文件>` 全自动）。

---

## 四、自动化链路

```bash
# 任意状态 → Android → 写 ESP（+可选 rootfs）→ 引导 → 串口自检
bash 02-工具/83-auto-cycle.sh --efi C:/Users/duoya/AppData/Local/Temp/mi8flash/BOOTAA64-xxx.efi
bash 02-工具/83-auto-cycle.sh --efi <efi> --rootfs /root/rootfs-4g.img
```

- 设备在 Linux → 串口 `sync; reboot` 回 Android（**不需要人工按键**）
- 设备在 fastboot → `erase misc` + reboot
- 写盘全部 md5 双校验（push 后 + 落盘后）
- 引导后自动等 COM + 发 `echo AUTO_OK_n` 确认 shell 可达

---

## 五、遗留

- [ ] WiFi QMI 的 `IPCRTR` 通道（见 §2.3）
- [ ] `10-usb0.network` 未被 networkd 接管 → 已用 `usb0-static.service` 绕过；若要 DHCP 可后续修
- [ ] `/lib/modules` 不存在（纯内建内核，`systemd-modules-load` 失败无害）
- [ ] 屏幕/触摸/指纹（第三方屏，优先级最低）
- [ ] `rootfs-4g.img` 的 md5 会因 `mount -o loop` 默认 rw 而变化 → 核查一律 `-o ro,noload`
