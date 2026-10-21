# Xiaomi Mi 8 UD (equuleus) — Mainline Linux Debian Port

**SDM845 · mainline 6.19.14 · UEFI (edk2-msm) · Debian 13** — with a fully documented, root-caused **WiFi bring-up** on a self-built stack. 中文文档为主（证据链完整）。

> 状态：Debian 13 可日常引导与联网。WiFi（WCN3990 / ath10k_snoc）已打通并联网验证；屏幕/触摸为进行中的并行工作线；电池/充电未开始。

## 为什么这个仓库有价值

社区里 845 机型的 WiFi 可用性通常来自"成品镜像"（预配 pd-mapper/rmtfs/固件）。本项目在**完全自建**的组合（自编 edk2-msm UEFI + 最新主线内核 + 手工 debootstrap rootfs）上，把 WiFi 从零逐环打通，**每一环有日志级证据**，并对症状与 [Kali #9780](https://bugs.kali.org/view.php?id=9780)（一加 6T，至今 open）完全一致的问题给出了独立解法：

```
rmtfs enumerate bug（内核按节点名前缀匹配 vs 本机 memory@f6301000）
 → MPSS 读 EFS 共享内存被 TZ 拦（需 qcom_scm_assign_mem 授权）
 → rmtfs_auth.ko（40 行极简授权模块，绕过 ACPI-glue oops）
 → MPSS 必须用本机原厂固件三件套（mba+modem.*+wlanmdsp，通用包固件配对不过）
 → tqftpserv 路径 translate 到 /lib/firmware/qcom/<soc>/<device>/
 → wlanfw (QRTR svc=0x45) 注册 → ath10k_snoc probe → wlan0 → 联网
```

关键修复与全部踩坑（内核手工模块构建 7 坑、`systemd-udevd` 缺件导致 uevent 链断裂等）见 `docs/24-*`、`docs/25-*`。

## 硬件与基线

| 项 | 值 |
|---|---|
| 设备 | 小米 8 屏下指纹版（equuleus / polaris DT），SN 225bd9ea |
| SoC | SDM845，A-only 单槽，vbmeta/dtbo 全 0（AVB 断） |
| 引导 | xbl → abl → boot 分区(edk2-msm UEFI) → ESP BOOTAA64.EFI → mainline 6.19.14 |
| 连接 | USB CDC-NCM（169.254.1.1）+ gadget 串口 ttyGS0 |
| WiFi | WCN3990 / ath10k_snoc，SSID 已连 5GHz 验证，HTTP/DNS 通 |

## 仓库结构

```
docs/            28 份中文技术文档（根因链/取证/归档/可行性报告/跨会话协作手册）
tools/           设备工具（mkboot_v1.py、83-auto-cycle.sh、com_probe.py 等 62 个）
tools/kernel-build/  手工构建内核模块的 18 个脚本（绕开 6.19 modpost 坑）
patches/rmtfs/  patch 后的 rmtfs 源码（enumerate/storage/SIGBUS 三补丁）
install/         安装指南 + 一键安装器（单版本制安装包配套）
collab/          主/副会话协作记录（工作方式透明化）
```

## 复现要点（不含任何专有固件）

1. **固件全部来自你自己的设备**：`mpss` 三件套从原厂 NON-HLOS（modem 分区）提取——`docs/21`/`docs/25` 有 dd/提取命令；本仓库不含任何高通专有 blob。
2. **rmtfs**：Debian `rmtfs` 包 + `patches/rmtfs/` 三补丁重编（`-o /var/lib/rmtfs` 目录模式）。
3. **rmtfs_auth.ko**：`tools/kernel-build/build_auth.sh` 一键构建（7 坑注意事项在脚本注释与 docs/24）。
4. **rootfs**：debootstrap + 首启 `resize2fs` 机制；`install/安装指南.md` 是完整装机手册（含单版本迭代规则）。
5. **wlanmdsp.mbn 必须与你的 modem 固件版本配对**（`rsize` 请求会暴露期望大小）——这是本次最隐蔽的一环。

## 声明

- 文档中的凭据已脱敏（WiFi 密码、账号替换为占位符）；SSH 私钥不随仓库分发。
- 本仓库**不包含**任何厂商专有固件 blob；使用你自己的设备备份。
- 代码 GPL-3.0（见 LICENSE）；文档 CC BY-SA 4.0（自由转载，注明出处）。
- 刷机有变砖风险；`fastboot flash boot` 前确保有可恢复的锚点镜像。

## 参考与致谢

- [Kali #9780](https://bugs.kali.org/view.php?id=9780)（fajita 同症状问题单——本仓库的解法可直接回帖）
- [linux-msm/tqftpserv](https://github.com/linux-msm/tqftpserv)、pd-mapper/rmtfs 生态
- Renegade Project（edk2-msm UEFI）
- mainline ath10k/qcom_scm 上游开发者（Baryshkov 等）
