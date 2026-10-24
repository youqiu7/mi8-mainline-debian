# 交接 HANDOFF — 小米8 屏下指纹版（equuleus）Debian 移植

> 导出于 2026-10-23 01:10。接手会话请先读 `00-文档/34-权威总快照-20261023-0100.md`（唯一权威状态），本文是操作级交接。

## 1. 设备与连接

- 小米8 屏下指纹版（equuleus，SDM845，serial 225bd9ea）
- SSH：`ssh -i F:\小米刷机\米8移植debian\02-工具\dagu_key root@10.55.0.1`（备用 169.254.1.1）【35号归档：原 Temp 路径会被系统清理，key 已复制进项目】
- fastboot：`F:\小米刷机\dagu移植debian\new-chat-1\platform-tools\platform-tools\fastboot.exe`（跨项目依赖 dagu 目录）
- 串口：设备侧 ttyGS0（USB serial gadget）；Windows 侧 COM 口以设备管理器实时为准（25号时代记过 COM7）
- 恢复通道（三次实战验证）：`fastboot flash mindowsesp <03-备份\锚点-20261022-0040\02-配置层\esp-full-20261022.img>` + `fastboot continue`
- WSL 内核构建环境：`wsl.exe -d Debian -u root`，树在 `/root/k619/linux-6.19.14`，编译用 clang19（`CC=clang`，PATH 加 /usr/lib/llvm-19/bin），**initramfs 必须用 `/root/initramfs-full`**

## 2. 当前设备状态（10-24 11:30 硬件层收官）

- **硬件层适配工作已由用户宣布结束**。运行 **v53b**（8db9d107）=终态版本：WiFi/BT/屏幕断电/充电守护全通
- **主连接通道：`ssh root@equuleus.local`**（mDNS 走 WiFi，IP 漂移不失联）；USB 10.55.0.1 兜底；串口 COM7 最后防线
- **屏幕物理断电保护**：开机仅 milogo 数秒亮；**换屏恢复=删 panel-samsung-ea8074.c 的 `MI8: damaged panel` 3 行 hack 重编**（27号§7）
- **充电守护运行中**：mi8-charge-guard（<40% 开充 1.5A QC DCP / >80% 停充微补 50mA，USB 直供服务器模式；阈值 /etc/default/mi8-charge-guard；39号）
- **相机 ⏸ 挂起**（37号+38号 RESUME 手册+锚点-20261023-1730，需硬件测量）；**音频/触摸 ⏸ 未开始**（33号/32号预案，**严禁发声**约束仍在）
- 后续方向=**服务器应用层**（用户目标：长期插电 Linux 服务器，由用户指定具体服务）

## 3. 当前任务（用户 2026-10-23 07:40 二次拍板，替代原 01:05 版）

1. ~~黑屏持久化~~ **✅ 完成**（08:00）：`black-screen.service`（rootfs oneshot：解绑 fbcon+写黑 fb0），重启自恢复验收通过。边界：背光无法软关（#48 无 backlight 节点）
2. ~~DT 路线~~ **✅ dtb= 打通（v19c，08:30）**：`fdtoverlay=` 机制不存在（35号§1）→ `dtb=` 完整替换实证成功——`mi8-stub-path=cmdline-dtb` + marker 节点进内核 FDT + **换 dtb 文件零内核重编**。四大坑见 35号§1.1（secureboot gate/判据陷阱/fdt_pack 时机/ABS64 禁令）。当前 ESP=v19c EFI + marker dtb（每次开机可自证链路）
3. ~~蓝牙~~ **✅ 完成（v22，10:30）**：根因=BD 地址无效被 MGMT 隐藏（moarchy 定案）→ dtb 加 `local-bd-address` 零重编修复。**安装包已归档 20261023-r3**（9/9 md5）
4. ~~相机轮~~ ⏸ **挂起（17:40，待硬件测量）**：v23-v47 四摄双战线（主摄 IMX363/IR OV9282/副摄 S5K3M3 探测/前摄参数备齐）全部推进到“软件全绿、i2c 不应答”——时钟树（PLL2 手动 prepare 480M→24M 确认）、mux fs 全扫、供电/PD/地址/时序/社区+vendor 四方参数合并仍 NACK；**证据链：需 XVCLK 的全灭、不用 XVCLK/DVDD 的（EEPROM/actuator）全活 → 物理待测=DVDD(gpio99 LDO)+XVCLK pin**。**重启任务：38号（RESUME 手册）+37号（全程记录）+锚点-20261023-1730（EFI/dts/驱动/config/脚本全资产）**
5. **下一轮=音频**：严禁发声，只到声卡注册级；先定案 tas2557 vs wsa881x（33号+35号§3）→ 触摸（32号 st,fts@49）→ 充电（28号 SMB2+beryllium）。改 DT 流程：编辑 dts → dtc → 覆盖 ESP 两处 dtb → reboot（dtb= 零重编惯例）

## 4. 工作红线与纪律

- **定时自检**：一旦出现思维链自我复制/重复符号/绕圈等异常，**立即停止全部工作**等用户
- 写 rootfs/刷机前必须 SSH 实测在线；大批量文件分批写逐批验
- pkill 用精确匹配（-x），不用 -f
- WSL 复杂命令一律写脚本文件（内联必挂，已踩 7 次）
- 屏幕内容/原厂 blob 不进 GitHub（youqiu7/mi8-mainline-debian）
- 音频轮测试不得发声（深夜约束）
- 高风险改动前分层锚点（boot/配置/rootfs 独立备份）

## 5. 关键文档索引（00-文档/）

| 编号 | 内容 |
|---|---|
| 34 | **权威总快照**（当前唯一权威） |
| 26 | WiFi 全链修复终版（8环根因） |
| 27 | 屏幕轮：-22 修复全过程+initramfs 教训 |
| 28 | 充电轮：SMB2 驱动现成+beryllium 9行dts 姿势+qcom_fg 补丁线索 |
| 29 | Polaris/equuleus 差异清单+DT 铁律 |
| 31 | 相机轮：CAMSS 在树+OP6 先例+ISP 许可翻案（GPL） |
| 32 | 触摸轮：INT=tlmm31/RESET=tlmm32+stmfts 加两行 id |
| 33 | 音频蓝牙轮：驱动全在树+wcn3990 固件路径 |

## 6. 源码资产

- WSL `/root/micode`：MiCode dipper-q-oss（**含 equuleus-p0.dtsi 原厂参数**——触摸 gpio/panel 序列/相机接线）
- WSL `/root/initramfs-full`：完整 initramfs（从 V1 EFI 提取，重编必备）
- `C:\Users\duoya\AppData\Local\hermes\cache\scratch\sdm845-linux`：社区 6.18.2 全量仓（sdm845.config 金矿+充电/触摸分支）
- `scratch\techpack-camera`：原厂相机栈（GPL-2.0，8万行，ISP 长线选项）
- `F:\小米刷机\米8移植debian\05-跨会话\03-交付-副显示\原厂面板序列-equuleus-20261022.txt`：原厂屏序列存档

## 7. 构建-刷机标准循环

```
# 编译（WSL）：bash scratch/qdebs/disp-build-vXX.sh（模板见 v13 版）
# 刷机（设备在线时）：scp EFI → root@10.55.0.1:/root/ → mount -o rw /dev/sda22 /mnt/e → cp → sync → umount → reboot
# 挂死时：fastboot 恢复（见 §1）
# 判据：SSH 回线 + dmesg 目标行 + /sys 节点
```

## 8. 已知坑（快速参考）

- initramfs 残缺（fw 目录）→ panic "no working init"（v1-v6 六轮假挂死的根源）
- appended dtb 无效（EFI stub 用 UEFI FdtBlob）
- 中文 NTFS 路径 clone 大仓库必挂（aux.c 保留名）→ 先 ASCII 再解压进 WSL
- make syncconfig 假死 → `yes '' | make`
- v14 白刷教训：python 正则没匹配到实际代码写法，编译前必须 grep 确认改动生效
