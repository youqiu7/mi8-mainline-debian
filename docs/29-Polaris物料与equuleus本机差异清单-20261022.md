# 29-Polaris物料与equuleus本机差异清单-20261022

> 时间：2026-10-22 18:40 · 主会话（插入任务，纯离线对比）
> 目的：本项目基础物料（UEFI 内嵌 FdtBlob / mainline polaris.dts）源自 **MIX 2S (polaris)**，而本机是 **米8 屏下指纹版 (equuleus)** 且**屏幕/触摸/屏下指纹均换装第三方件**——本清单逐子系统列出差异，供后续查证避免"拿错参考"。
> 数据源：`01-资料/vendor-full.dts`（**本机 Android 全量 DT，equuleus 真身**）· mainline `kernel-dts/sdm845-xiaomi-polaris.dts` / `-dipper.dts` · 02号硬件实测。

## 1. 板级核心差异总表

| 子系统 | polaris 物料（MIX 2S） | dipper（米8标准版参考） | **equuleus 本机真身** | 移植影响 |
|---|---|---|---|---|
| **面板** | `jdi,fhd-nt35596s` | `samsung,ea8074` | **第三方 LCD**：DT compatible 沿用 jdi（UEFI blob 内），初始化序列=EA8074 系（02号§10 实测参数），真实 IC 未知（RDID 被 -22 挡住未读到） | UEFI blob 的 panel 节点靠 compatible **巧合**匹配到我们的驱动；**时序/序列必须以实测为准，勿信任何一家原厂参数** |
| **触摸** | `syna,rmi4-i2c`（Synaptics） | `focaltech,ft8719` | **`st,fts`**（ST，第三方换件） | **三家全不同**——主线/社区的 polaris、dipper 触摸方案**一个都不能抄**；Q3 已批"stmfts 改 of_match/无 fwnode 注册"路线 |
| **指纹** | 后置（主线无节点） | 后置（主线无） | **屏下光学**（goodix + Synaptics 双供应商节点，第三方换件） | 主线零支持（22号"确定性缺口"），短期无解 |
| **电池计量** | `simple-battery`（占位，无真实数据源） | 同占位 | `qcom,fg-gen3`（PMIC 内置 fg，SPMI 上） | **polaris 的 simple-battery 不可用**（拿不到真电量）；fg-gen3 主线无驱动——电量可见性是独立课题 |
| **充电** | polaris.dts **无 charger 节点**（仅 PMIC rpmh-regulators） | 无 | `qcom,qpnp-smb2` + **`qcom,smb1355`×2**（QC4+ 双电荷泵） | mainline `pmi8998.dtsi` 的 `qcom,pmi8998-charger` 与 vendor 的 `qpnp-smb2` **不同名**——即便 DT 节点生效，compatible 也要么换名要么加 of_match；**QC4+ 泵（smb1355）主线无驱动**（快充先放，5V 慢充 PMIC 硬件自主） |
| **音频 smartpa** | （tas 系未在 polaris.dts） | `ti,tas2557` | vendor: wsa881x×4 + cdc（沿用） | 08/22 号已列 P 级，非本轮 |
| **WiFi/BT** | `wcn3990-bt` + rmtfs-mem | 同 | 同（硬件同款） | **无差异**——WiFi 修复链对 polaris/dipper 物料通用 ✓ |
| **NFC/GPS** | 节点未以常见 compatible 表达 | — | vendor DT 中无 nfc/gps compatible 命中（待深挖表达形式） | 标注待查 |

## 2. 对"用 polaris 物料"路线的三条铁律

1. **凡板级外设（屏/触摸/指纹/电池/充电）**：polaris 物料只能当"接线图参考"（reg/interrupt/spmi 地址布局同源度高），**compatible 与参数必须以 equuleus 实测/vendor DT 为准**。
2. **UEFI FdtBlob 的生效优先级高于 appended dtb**（本轮实证：副会话拼接 dtb 从未生效，panel 计数=0 但内核匹配到了 panel——EFI stub 用 UEFI 的 FDT config table）→ **任何 DT 修复必须走 `fdtoverlay=`（EFI stub 支持）或 FV 内嵌 blob 替换**，改 appended dtb 无效。20号"dtb 陷阱"的深层机制即此。
3. **dipper 反而是更好的板级参考**（面板 ea8074 同系、同为米8 家族），但触摸仍是第三家（ft8719 vs 本机 st,fts）。

## 3. v4 SMBB 挂死的重新解读（结合本清单 + sdm845-mainline 弹药，二次修正）

- vendor 充电 compatible=`qcom,qpnp-smb2`（Android 体系）；但我们**拼接 dtb include 的 mainline `pmi8998.dtsi` 里的 charger 节点 compatible 正是 `qcom,pmi8998-charger`**——**SMBB=y 时该节点会被 probe**（一次修正时说"不同名不会 probe"是错的——两套体系并存于各自 DT，我们 dtb 里的就是 mainline 节点）。
- v4（config +SMBB=y）挂死 → **`qcom_smbb` 对我们 dtb 里该节点的 probe 挂死实锤**（大概率=节点属性不完整（vbus-supply/中断/gpio phandle 缺）导致 probe 深层路径异常）。
- **社区弹药**（gitlab sdm845-mainline 分支 `b4/pmi8998-charger-dts`，2023）：`b9e83457` pmi8998.dtsi add charger node（我们已有）+ `93a7901d` oneplus enable（**解锁 bootloader 500mA 限制**）+ `1f8ac528` axolotl enable（**含 smb1355 并联充电节点——smb1355 主线有启用先例**，29号§1 的"QC4+ 泵主线无驱动"需按此降级修正）+ `f8b01ae8` **xiaomi beryllium enable**（家族先例）→ **充电轮下一步=拿这 4 个 commit 的 diff 对照我们 dts 补全节点属性**。

## 4. 关联文档
- 02号（本机硬件实测）· 17号（实机 FdtBlob 全览）· 27号（屏幕挂死分析）· 28号（充电轮）· 22号（全驱动差距）
