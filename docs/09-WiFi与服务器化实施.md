# WiFi 与服务器化实施记录（2026-10-21 00:03）

## 一、目标（按用户 2026-10-20 指令）

- ❌ 不要桌面 → 纯服务器
- ❌ 不要 USB 网络（RNDIS）
- ✅ **WiFi 联网**：`OPPO A5-5G` / `<WIFI_PASSWORD>`
- ✅ 用户：`youqi` / `<WIFI_PASSWORD_ALT>`
- ✅ 先保证 Debian 能跑起来

## 二、WiFi 硬件与驱动路径

SDM845 + **WCN3990**（集成，走 SNOC）→ 驱动 `ath10k_snoc`

```
sdm845.dtsi: wifi@18800000  compatible="qcom,wcn3990-wifi"
  供电（板级 DTS 必须给）：
    vdd-0.8-cx-mx  ← vreg_l5a_0p8
    vdd-1.8-xo     ← vreg_l7a_1p8
    vdd-1.3-rfa    ← vreg_l17a_1p3
    vdd-3.3-ch0    ← vreg_l25a_3p3
    vdd-3.3-ch1    ← vreg_l23a_3p3
```

原 DTS 里 `&wifi { status = "disabled"; }`（P1 阶段主动禁的），现已改为 `okay` 并补齐 5 路供电。

## 三、内核配置踩的两个坑（关键）

### 坑 1：`=m` 等于没有

这套方案**不带 modules 目录**（纯 Image + 内建 initramfs），所以 WiFi 相关必须全部 `=y`：

```
CFG80211=y  MAC80211=y  ATH10K=y  ATH10K_SNOC=y
QCOM_QMI_HELPERS=y  QCOM_SMEM=y  QRTR=y
```

### 坑 2：`QCOM_RPROC_COMMON` 是隐式符号，手动 `=y` 会被重算

`drivers/remoteproc/Kconfig`:

```kconfig
config QCOM_RPROC_COMMON
	tristate          ← 没有提示符 = 隐式符号，值由依赖它的符号推导
	select AUXILIARY_BUS
```

而 `ATH10K_SNOC` 写的是 `depends on QCOM_RPROC_COMMON || QCOM_RPROC_COMMON=n` ——
既然没有 `=y` 的使用者，`QCOM_RPROC_COMMON` 永远被算成 `m`，于是 `ATH10K_SNOC` 也只能 `m`，
`olddefconfig` 会把手工设的 `=y` 打回 `=m`。

**修法（已改源码）**：

1. `drivers/remoteproc/Kconfig`：`QCOM_RPROC_COMMON` 由 `tristate` 改为 `bool`
2. `drivers/net/wireless/ath/ath10k/Kconfig`：`ATH10K_SNOC` 的
   `depends on QCOM_RPROC_COMMON || QCOM_RPROC_COMMON=n` 改为 `select QCOM_RPROC_COMMON`

原始文件备份在 `/root/ath10k-Kconfig.orig`、`/root/remoteproc-Kconfig.orig`。

### 坑 3：`qcom_common.c` 无条件调用 glink

`QCOM_RPROC_COMMON=y` 后内建了 `qcom_common.o`，它**没有 `IS_ENABLED` 保护**就调用
`qcom_glink_smem_register()`，而 `RPMSG_QCOM_GLINK_SMEM` 还是 `=m` → 链接报
`undefined reference to qcom_glink_smem_register`。

**修法**：`RPMSG_QCOM_GLINK_SMEM` 也内建 `=y`（用 `scripts/config --enable`，`sed` 改不动这个符号）。

## 四、固件

`firmware-atheros` 包（Debian 官方，需先给源加 `non-free-firmware` 组件）：

```
/lib/firmware/ath10k/WCN3990/hw1.0/
    firmware-5.bin        ← 主固件
    wlanmdsp.mbn          ← DSP 镜像
    board-2.bin           ← 板级数据
```

共 7.9 MB。**没有这些固件，ath10k probe 会直接失败**，dmesg 里是 `Direct firmware load failed`。

## 五、rootfs 内容

| 项 | 值 |
|---|---|
| 来源 | debootstrap trixie arm64 minbase（239 MB） |
| 镜像 | `rootfs-4g.img`，4 GB，ext4，label **`debian-root`** |
| 用户 | `youqi` / `<WIFI_PASSWORD_ALT>`（uid 1000，sudo 组） |
| root | 密码 `<WIFI_PASSWORD_ALT>`（串口应急） |
| WiFi | `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf`：`OPPO A5-5G` / `<WIFI_PASSWORD>`，`country=CN` |
| 网络 | `systemd-networkd` 的 `25-wlan.network`，DHCP |
| 时钟 | `first-boot.sh` 里 `date -s` 先对时（无 RTC，否则 apt HTTPS 全失败），之后装 `fake-hwclock` |
| 扩容 | `first-boot.sh` 里 `resize2fs` 到分区实际大小（59 GB） |
| 串口 | `serial-getty@ttyGS0` override，115200 |

## 六、最终产物

```
C:\Users\duoya\AppData\Local\Temp\mi8flash\BOOTAA64.EFI   41,624,935 B  md5 d8a56dd1…
    └ Image 41,523,712（含 ath10k_snoc）+ dtb 101,223（wifi okay）
C:\Users\duoya\AppData\Local\Temp\mi8flash\rootfs-4g.img   4 GB ext4 label debian-root
```

cmdline：`console=tty0 console=ttyGS0 earlycon=qcom_geni ignore_loglevel loglevel=8 fbcon=map:0 acpi=off dtb=/equuleus.dtb`

## 七、待验证（设备开机后）

1. `DT model` 是否变成 `Xiaomi Mi 8 UD`（`dtb=` 生效）
2. `dmesg | grep ath10k` 是否 probe 成功
3. `ip link` 是否出现 `wlan0`
4. `wpa_supplicant` 能否连上 `OPPO A5-5G`
5. `resize2fs` 是否扩到 59 GB
