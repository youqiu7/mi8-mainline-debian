# 51-WiFi 5G 与电源键唤醒-三重根因与定案-20261104

> 前置文档：`50-4G数据通路与NetworkManager迁移-20261104`（NM 迁移背景）、`48-suspend唤醒-Phosh桌面-中文环境-20261104`
> 本文档记录 5G WiFi 从「完全不可用」到「212/195 Mbps 满速」的完整定案，以及电源键无法亮屏的根因与修复。
> 结论均来自实机取证，所有推翻过的判断单独列在第 6 节。

---

## 1. 最终状态（实机实测，2026-11-04 19:0x）

| 项目 | 结果 |
|---|---|
| SSID / 频段 | `OPPO A5-5G` / ch36 5180.0 MHz |
| 信号 | -49 ~ -54 dBm |
| PHY 速率 | **270.0 MBit/s MCS 15 40MHz**（HT40 满速） |
| iperf3 下载 | **212 Mbits/s** |
| iperf3 上传 | **195 Mbits/s** |
| ping 网关 | **1.304 ms**（抖动 0.513），0% 丢包 |
| 加密协商 | WPA2-PSK + CCMP + PMF(ieee80211w=2) |
| 固定 MAC | `02:8d:5a:32:6b:d0`（重启不变） |
| 开机行为 | 自动连接 5G，无需人工干预 |

**2.4G 对照**（兜底链路，非主用）：35.8 / 20.1 Mbps，ping 网关 71 ms（抖动 48 ms），PHY 108 MCS11 40MHz。

---

## 2. 最终架构：四层分工，互不抢接口

这是本次定案的核心。**同一时刻只能有一个 wpa_supplicant 控制 wlan0**，因此把职责按层切开：

```
┌─ udev ─────────── /etc/systemd/network/20-wlan0.link
│                    [Link] MACAddress=02:8d:5a:32:6b:d0
│                    作用：开机设 MAC，解决 ath10k "invalid MAC; choosing random"
│
├─ wpa_supplicant ─ /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
│                    OPPO A5-5G  priority=20   ← 优先
│                    OPPO A5     priority=10   ← 兜底
│                    服务：wpa_supplicant@wlan0.service（enabled）
│
├─ networkd ─────── /etc/systemd/network/20-wlan0.network
│                    DHCP=ipv4 + DNS 223.5.5.5 / 119.29.29.29
│
└─ NetworkManager ─ /etc/NetworkManager/conf.d/99-mi8-unmanaged.conf
                     unmanaged-devices=interface-name:wlan0;interface-name:p2p-dev-wlan0
                     作用：NM 继续管 usb0 / 4G，但**不碰 wlan0**
```

**铁律**：`wpa_supplicant@wlan0.service` 与 NM 接管 wlan0 **不可共存**。二选一，本机选前者（为了 5G 满速）。

---

## 3. 三个真根因（按影响排序，均已实机证实）

### 根因 1：两个 wpa_supplicant 抢 wlan0（最致命）

实机 `ps` 取证：

```
PID  836: /usr/sbin/wpa_supplicant -u -s -O DIR=/run/wpa_supplicant   ← NM 用的 D-Bus 实例
PID  923: /usr/sbin/wpa_supplicant -c.../wpa_supplicant-wlan0.conf -iwlan0  ← systemd 独立实例
```

两者同时运行导致：

| 现象 | 解释 |
|---|---|
| `iw dev wlan0 link` 显示已连接 | 独立实例自己连上了 AP |
| `nmcli device status` 显示 `disconnected` | NM 的 supplicant 根本没控制到接口 |
| `nmcli connection up` 报 "could not be found" | NM 的扫描结果永远为空 |
| 没有 IPv4 | NM 不认为激活成功，不跑 DHCP |

**修复**：`systemctl mask wpa_supplicant@wlan0.service`（NM 管时），或反过来让 NM unmanaged（本机选择）。

### 根因 2：NM 的 supplicant 同时管理 p2p-dev-wlan0

即使让 NM 独占 wlan0，5G 仍认证失败。但**直接往 NM 的 supplicant 注入相同参数（SSID + PMK + WPA-PSK + ieee80211w=2）也失败**，而独立 supplicant 用同一套参数一次成功 → 证明是 NM 那个 supplicant 实例的问题。

**定位**：NM 会为同一块射频创建 `p2p-dev-wlan0`（P2P-device），占用射频调度。

**修复**：`/etc/NetworkManager/conf.d/` 加 `[device] wifi.p2p-enabled=false` → NM 立刻能连上 5G。

### 根因 3：NM 无条件用 WPA3-SAE，而 WCN3990 的 SAE 路径只有 1/4 性能

NM 连上后实测：

```
wpa_cli get_network 0 key_mgmt → SAE FT-SAE
```

而 AP 广播是 `[WPA2-PSK+SAE-CCMP][SAE-H2E]`（WPA2/WPA3 双模）。

**尝试强制 WPA2 全部失败**：

| 尝试 | 结果 |
|---|---|
| `key-mgmt=wpa-psk` | 仍协商 SAE |
| `key-mgmt=wpa-psk-sha256` | 仍协商 SAE |
| `pmf=1`（optional） | AP 强制 PMF，直接连不上 |
| `pairwise=ccmp` / `group=ccmp` | 生效但无效（不是 TKIP 问题） |

**性能对比（同一 AP、同一位置）**：

| 加密 | PHY | 下载 | 上传 | ping 网关 |
|---|---|---|---|---|
| **WPA2-PSK（wpa_supplicant）** | 270 MCS15 | **212 Mbps** | **195 Mbps** | **1.3 ms** |
| WPA3-SAE（NM） | 162~270 MCS12-15 | 45.6 Mbps | 35.7 Mbps | 48 ms（抖动 50） |

SAE 连接还伴随精确的 **100 ms 周期性延迟尖峰**：

```
102ms, 0.97ms, 1.02ms, 1.11ms, 101ms, 102ms, 102ms, 0.91ms, ...
```

**结论**：WCN3990 固件（ATH10K，2019 版）对 SAE 的处理效率极低，WPA2-PSK 是唯一能跑满 HT40 的路径。

---

## 4. WiFi 图标的取舍（已知限制，非缺陷未修）

**现象**：按上述架构连接后，Phosh 状态栏 WiFi 图标显示「断开」。

**原因**：Phosh 的 WiFi 图标数据源是 NetworkManager 的 `NMDeviceWifi` 状态。本机把 wlan0 设为 NM unmanaged，NM 无法报告该连接。

**为什么不能两全**：

| 方案 | 图标 | 速度 |
|---|---|---|
| NM 管 wlan0 | ✅ 正常 | ❌ 45 Mbps（强制 SAE） |
| wpa_supplicant 管 | ❌ 断开 | ✅ 212 Mbps |

NM 的 SAE 强制行为在 profile 层无解（第 3 节根因 3 已证）。**取速度，舍图标**。

**iwd 方案已试，失败**：`iwd.service` 启动即 `status=1/FAILURE`，重启 5 次后放弃——与 wpa_supplicant 争抢 wlan0。要彻底换 iwd 需先拆除可用栈，风险收益不成比例，搁置。

**查看真实 WiFi 状态的命令**：

```bash
iw dev wlan0 link                        # 权威：关联状态、频率、速率
ip -4 -br addr show wlan0                # IP
systemctl status wpa_supplicant@wlan0    # 连接服务
```

---

## 5. 电源键无法亮屏 / 黑屏

### 5.1 电源键被 logind 吞掉（真根因）

```ini
# /etc/systemd/logind.conf.d/10-mi8-server.conf （错误配置）
HandlePowerKey=lock
```

`HandlePowerKey=lock` 让 **systemd-logind 拦截电源键事件**，phosh 收不到按键，因此「按电源键亮屏」永远无效。

**修复**：

```ini
HandlePowerKey=ignore        # 事件交给 phosh，由 phosh 处理熄屏/亮屏
HandleSuspendKey=ignore
IdleAction=ignore
IdleActionSec=0
```

> 这是"服务器模式"改造时引入的设计错误：本想禁止休眠，却把按键一起吞了。

### 5.2 黑屏：`pkill phosh` 后 gdm 不重生 shell

`pkill -x phosh` 只会杀掉 shell，**gdm 不会重新拉起**，导致 phoc 还在跑但无 UI，DPMS 自动关闭：

```
backlight: brightness=1094  bl_power=4     ← 背光关断
card0-DSI-1: dpms=Off  enabled=disabled
phosh 主进程：不存在
```

**修复**：`systemctl restart gdm`（会重建 session）。之后状态应为：

```
bl_power=0  brightness=4095
dpms=On  enabled=enabled
phosh / phoc / phosh-osk-stub 全部运行
LockedHint=no
```

**教训**：**不要用 `pkill phosh` 重启桌面**，用 `systemctl restart gdm`。

---

## 5c. 刘海屏适配（状态栏时钟被遮挡）

### 现象

小米8 是 1080×2248 的宽刘海屏。**刘海尺寸以小米官方开发者文档为准：宽 560px、高 89px**（来源：<https://dev.mi.com/console/doc/detail?pId=1293>，该表列出小米8 `dipper` 为 1080×2248 / Notch 高 89 / Notch 宽 560 / DPI 440）。居中即 x 260–820，占屏宽 **51.9%**，与 iPhone X 的约 55% 属同一量级。

Phosh 顶栏默认把**时钟放在正中**，正好落在刘海下方，完全看不见；左侧图标（WiFi/蓝牙）和右侧（电池）反而正常。

### 原理

Phosh 从 **0.29.0** 起会自动避让刘海——前提是能拿到设备的面板数据。数据由 **gmobile** 库提供，编译在 `libgmobile.so.0` 的 gresource 里：

```
/org/gnome/gmobile/devices/display-panels/<device-tree-compatible>.json
```

Debian 13 的 `libgmobile-common 0.3.1` 内置了 daria / fairphone / furilabs / gigaset / moto / nothing / oneplus / purism / **xiaomi,beryllium（Poco F1）** 等，**没有小米8**。

### 解决

按官方文档 [Avoiding notches](https://phosh.mobi/posts/notch-support/) 用 `G_RESOURCE_OVERLAYS` 覆盖法补数据，无需重新编译：

**1. 写面板数据** `/usr/share/gmobile-overlay/xiaomi,polaris.json`：

```json
{
  "name": "Xiaomi Mi 8",
  "x-res": 1080,
  "y-res": 2248,
  "cutouts": [
    { "name": "notch", "path": "M 260,0 h 560 v 89 h -560 Z" }
  ]
}
```

坐标以屏幕左上角为原点；`path` 是 SVG 路径，`h 264` 是水平画 264px，`v 92` 是垂直 92px。

**2. 注入环境变量** `/etc/profile.d/50-gmobile-overlay.sh`：

```sh
export G_RESOURCE_OVERLAYS=/org/gnome/gmobile/devices/display-panels=/usr/share/gmobile-overlay
```

**为什么用 `/etc/profile.d/` 而不是 `environment.d`**：phosh 由 `gdm-wayland-session` → `/usr/bin/phosh-session` → `bash -lc 'exec gnome-session --session=phosh'` 启动。`environment.d` 只对 systemd user manager 生效（实测无效），而 `bash -lc` 会读 `/etc/profile.d/*.sh`，环境变量沿 gnome-session 传递给 phosh（实测 `/proc/<phosh>/environ` 可见）。

**3. 生效**：`systemctl restart gdm`（或重新登录）。

### 验证结果（实机截图对比，坐标换算回 1080 宽度）

| | 修改前 | 修改后 |
|---|---|---|
| 时钟位置 | x≈470–610（**在刘海内**） | x≈920–1000（**刘海右侧**） |
| 刘海区域 x 260–820 | 被时钟占用 | **时钟已移出；静音图标仍压在边缘** |
| 顶栏元素顺序 | 左5图标 → 中间时间 → 右电池 | 左5图标 → 右：静音、电池、时间 |

> 注：560px 刘海让两侧各只剩 260px（87dp），而本机有 8 个状态图标，因此「静音」仍与刘海边缘重叠。若要让全部图标露出，可把宽度收到约 480px 换取，代价是时钟位置略往中间回。**优先保证时钟可见**（信息价值最高），其余图标按需取舍。

### 如果刘海尺寸不准

`560×89` 来自小米官方开发者文档（`pId=1293` 表中 `dipper` 一行），**以官方值为准，不要按 dp 估算**——按 88dp×scale3 估出的 264px 只有真实宽度的一半，实测明显偏小。

如需微调：改 JSON 里的 `h`（宽）、`v`（高）与 `M` 起点 x 坐标后 `systemctl restart gdm`。也可参考 LineageOS 的 cutout overlay（`android_device_xiaomi_polaris`/`equuleus` 的 `config_mainBuiltInDisplayCutout`），并可用 PiotrZPL 的 `lineage_cutout_to_gmobile` 脚本转换成 gmobile 格式，但**必须在真机上目视校验**。

---

## 6. 锁屏（当前已关闭）

用户为服务器用途，锁屏无实际价值，且 OSK 按键在锁屏下存在已知问题（见 7 节）：

```bash
sudo -u youqi DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  gsettings set org.gnome.desktop.screensaver lock-enabled false
sudo -u youqi DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  gsettings set org.gnome.desktop.screensaver idle-activation-enabled false
```

**注意**：Phosh 的锁屏不走 logind，`loginctl unlock-session` 无效（`LockedHint` 仍是 yes）。只能靠 gsettings 关闭或重启 gdm。

---

## 7. 已知遗留问题

| 问题 | 状态 | 说明 |
|---|---|---|
| **锁屏 OSK 按键无效** | 搁置（用户同意） | 键盘能弹出、滑动正常、单指点击在普通应用中正常（见 46 号文档），唯独 **Phosh 锁屏界面**按键不生效。已通过关闭锁屏绕过。未定位到根因 |
| **WiFi 图标显示断开** | 已确认为硬取舍 | 见第 4 节 |
| 2.4G 速率偏低 | 兜底可接受 | 35.8/20.1 Mbps，空口拥挤（ping 抖动 48ms）。2.4G 仅作 5G 失败时的兜底 |
| 幽灵 LEAVE 心跳 | 已缓解，未根除 | `ev_leave_dropped` 累计 1.5 万+/20min。驱动层丢弃未按下 slot 的 LEAVE；若按住期间固件也吐 LEAVE，理论上会误判抬手（未实测到，暂不改） |

---

## 8. 回滚与备份

| 路径 | 内容 |
|---|---|
| `/root/wifi-207-snapshot/` | 当前可用配置完整快照（nm-conf.d / network.d / wpa conf / nm-connections） |
| `/root/wifi-b-plan-backup/` | B 方案实施前备份 |
| `/root/b-plan-backup/` | 早期 networkd 备份 |
| `/root/networkd-disabled/` | 迁移 NM 时移走的原始 networkd 单元（`10-usb0.network`、`20-wlan0.network`、`20-wlan.network`） |
| `/root/wifi-p2p-test-backup/` | P2P 实验前备份 |
| `oppo5g.nmconnection.bak-*` | NM profile 多份历史版本（含 `.bak-tkip`、`.bak-sha256`） |

### 回滚到「NM 管 wlan0」模式（如果将来需要图标）

```bash
# 1. 恢复 NM 接管
rm -f /etc/NetworkManager/conf.d/99-mi8-unmanaged.conf
cat > /etc/NetworkManager/conf.d/99-mi8-nm5g.conf <<'EOF'
[device]
wifi.p2p-enabled=false
wifi.scan-rand-mac-address=no
wifi.powersave=2
EOF
# 2. 停独立 supplicant，交给 NM
systemctl disable --now wpa_supplicant@wlan0.service
rm -f /etc/systemd/network/20-wlan0.network
# 3. 重启
systemctl restart NetworkManager
nmcli connection up oppo5g
```

预期结果：图标正常，速度降至 ~45 Mbps。

---

## 9. 关键取证命令清单

```bash
# —— 谁是 wlan0 的主人 ——
ps aux | grep wpa_supplicant | grep -v grep        # 必须只有 1 个实例
pgrep -a wpa_supplicant

# —— NM 视角 ——
nmcli -t -f DEVICE,STATE,CONNECTION device status | grep wlan0
nmcli device show wlan0 | grep -E "GENERAL.STATE|NM.MANAGED"

# —— 实际协商参数（决定性）——
wpa_cli -p /run/wpa_supplicant -i wlan0 status | grep -E "key_mgmt|wpa_state"
wpa_cli -p /run/wpa_supplicant -i wlan0 get_network 0 key_mgmt
wpa_cli -p /run/wpa_supplicant -i wlan0 get_network 0 pairwise

# —— 链路质量 ——
iw dev wlan0 link | grep -E "SSID|freq|signal|rx bitrate"
ping -c 20 -i 0.3 192.168.10.1          # 看是否有 100ms 周期尖峰（SAE/powersave 特征）

# —— NM 失败原因（ssid-not-found 是误导性归类）——
journalctl -u NetworkManager -n 80 --no-pager | grep -iE "secrets|assoc|scan|activat"
```

---

## 10. 本次推翻的错误判断（务必记住）

| 曾经的判断 | 真相 |
|---|---|
| 「5G 连不上是 DFS 信道问题」 | ch36 也失败；DFS 只是次要因素，主因是 MAC 随机 + supplicant 冲突 |
| 「`cloned-mac-address` 已生效」 | `nmcli connection modify` 曾静默失败，keyfile 里根本没写进去 |
| 「`mac-address-randomization=0` = 不随机」 | **0 = default，1 = never**。之前所有 `=0` 的设置等于没设 |
| 「`ath10k invalid MAC; choosing random` 是根因」 | 是症状；根因是 `20-wlan0.network` 的 `[Link] MACAddress` 被移走 |
| 「NM 报 ssid-not-found = 找不到网络」 | NM 把「secret 缺失」也归到这个 reason。真实原因是 psk 存成 64 位 hex 被当 passphrase 处理 |
| 「pairwise 里的 TKIP 导致降速」 | 改成纯 CCMP 后速度不变，真凶是 SAE |
| 「bgscan 导致周期性延迟」 | 关掉 bgscan 后 100ms 尖峰依旧，是 SAE/powersave 路径 |
| 「`HandlePowerKey=lock` 是安全的服务器配置」 | 它吞掉电源键，导致无法亮屏 |

---

**归档时间**：2026-11-04
**设备**：Xiaomi Mi 8 (equuleus)，内核 6.19.14，Phosh 0.46
**验证方式**：全部结论来自实机 `iw` / `wpa_cli` / `nmcli` / `iperf3` / `journalctl` 输出
