# 20261104-v95-wifi5g — WiFi 5G 满速 + 电源键修复

小米 8（equuleus）Debian 13 / Phosh 0.46 的 WiFi 5G 定案配置包。

- **实测性能**：5G 下载 **212 Mbits/s**、上传 **195 Mbits/s**、ping 网关 **1.3 ms**
- **对比基线**：2.4G 仅 35.8 / 20.1 Mbps、ping 71 ms
- **完整分析**：`00-文档/51-WiFi-5G与电源键-三重根因与定案-20261104.md`

---

## 1. 适用条件

| 项 | 要求 |
|---|---|
| 设备 | Xiaomi Mi 8 (equuleus)，SDM845，WCN3990 |
| 系统 | Debian 13，内核 6.19.14（ath10k） |
| 路由器 | OPPO A5 双频（2.4G `OPPO A5` / 5G `OPPO A5-5G`），5G 在 **非 DFS 信道**（本机为 ch36） |
| 前提 | 路由器做了 MAC 绑定，必须使用固定 MAC `02:8d:5a:32:6b:d0`（或改成你自己的） |

**重要**：5G 必须避开 DFS 信道（ch52–64 / ch100–144）。WCN3990 固件不实现 CAC，DFS 信道标记 `no IR`，无法主动发射。请把路由器 5G 固定在 **ch36–48 或 ch149–165**。

---

## 2. 快速使用

```bash
# 在设备上（root）
cd /root/v95-wifi5g
bash apply.sh
```

脚本会自动：
1. 备份现有配置到 `/root/v95-wifi-backup-<时间戳>/`
2. 安装 udev MAC 固定规则
3. 配置 networkd DHCP
4. 生成/保留 wpa_supplicant 配置（5G priority=20 优先）
5. 修正 logind 电源键行为
6. 让 NM 不再管理 wlan0
7. 重启服务并验证

若已有含 `OPPO A5-5G` 的 wpa 配置，会保留不覆盖；否则会提示输入 WiFi 密码（2.4G/5G 相同）。

---

## 3. 架构：四层分工

```
udev          20-wlan0.link        → 固定 MAC（重启不变）
wpa_supplicant wpa_supplicant-wlan0.conf → 连接（5G 优先，2.4G 兜底）
networkd      20-wlan0.network     → DHCP + DNS
NetworkManager 99-mi8-unmanaged.conf → 不碰 wlan0，只管 usb0 / 4G
```

**核心铁律**：`wpa_supplicant@wlan0` 和 NetworkManager **不能同时管 wlan0**，否则会出现「`iw` 显示已连接但 NM 说 disconnected、没有 IP」的假死状态。这是本机最难查的一个坑。

---

## 4. 文件清单

| 文件 | 安装位置 | 作用 |
|---|---|---|
| `20-wlan0.link` | `/etc/systemd/network/` | udev 固定 MAC `02:8d:5a:32:6b:d0` |
| `20-wlan0.network` | `/etc/systemd/network/` | networkd DHCP + DNS |
| `wpa_supplicant-wlan0.conf.template` | `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` | 5G/2.4G 双网络，密码需自行填写 |
| `99-mi8-unmanaged.conf` | `/etc/NetworkManager/conf.d/` | 让 NM 放弃 wlan0 |
| `10-mi8-server.conf` | `/etc/systemd/logind.conf.d/` | 电源键交给 phosh（`HandlePowerKey=ignore`） |
| `xiaomi,polaris.json` | `/usr/share/gmobile-overlay/` | 小米8 刘海几何数据（让 Phosh 把时钟移到右侧） |
| `50-gmobile-overlay.sh` | `/etc/profile.d/` | 注入 `G_RESOURCE_OVERLAYS` 让 phosh 读到上面那份数据 |
| `apply.sh` | — | 一键应用 |
| `rollback.sh` | — | 回滚到 NM 管 wlan0（图标恢复，速度降到 ~45 Mbps） |

---

## 5. 已知取舍：WiFi 图标显示断开

Phosh 的 WiFi 图标数据源是 NetworkManager。本方案让 NM unmanaged wlan0，因此**图标会显示断开，但网络实际正常工作**。

原因：NM 在 AP 支持 SAE + PMF required 时会**强制使用 WPA3-SAE**，而 WCN3990 固件的 SAE 路径只有 WPA2 的四分之一性能（实测 45 vs 212 Mbps，且带 100ms 周期性延迟尖峰）。profile 层面无法阻止（`wpa-psk`、`wpa-psk-sha256`、`pmf=1` 均已实测无效）。

**查看真实状态**：
```bash
iw dev wlan0 link                          # 权威关联状态
ip -4 -br addr show wlan0                  # IP
systemctl status wpa_supplicant@wlan0      # 服务
```

---

## 6. 注意：不要在 NM 在线时启停 supplicant

以下操作会造成接口假死（`iw` 有连接、NM 无状态、无 DHCP）：

- 同时运行 `wpa_supplicant.service`（NM 用）和 `wpa_supplicant@wlan0.service`
- 在 NM 管理 wlan0 时又手工 `wpa_cli` 操作
- `systemctl restart systemd-networkd` 而 networkd 又配了 wlan0 的 IP（NM 管时）

排障第一步永远是：`pgrep -a wpa_supplicant` —— **必须只有一个实例**。

---

## 7. 相关文档

| 文档 | 内容 |
|---|---|
| `00-文档/51-WiFi-5G与电源键-三重根因与定案-20261104.md` | 完整根因分析、失败尝试记录、回滚步骤、取证命令 |
| `00-文档/50-4G数据通路与NetworkManager迁移-20261104.md` | NM 迁移背景 |
| `00-文档/48-suspend唤醒-Phosh桌面-中文环境-20261104.md` | Phosh 环境 |
| `00-文档/46-触摸轮-FTI协议定案与驱动落地-20261104.md` | 触摸驱动 |
