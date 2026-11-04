#!/bin/bash
# ============================================================
# 回滚：退回「NetworkManager 管 wlan0」模式
#   代价：WiFi 图标恢复正常，但 5G 会走 WPA3-SAE，速度降到 ~45 Mbps
#   用途：想恢复图形界面里能开关 WiFi 时使用
# ============================================================
set -e

[ "$(id -u)" -eq 0 ] || { echo "必须以 root 运行"; exit 1; }

echo "==> 把 wlan0 交还给 NetworkManager"
rm -f /etc/NetworkManager/conf.d/99-mi8-unmanaged.conf
cat > /etc/NetworkManager/conf.d/99-mi8-nm5g.conf <<'EOF'
[device]
wifi.p2p-enabled=false
wifi.scan-rand-mac-address=no
wifi.powersave=2
EOF

echo "==> 关闭独立 supplicant（避免抢接口）"
systemctl disable --now wpa_supplicant@wlan0.service 2>/dev/null || true

echo "==> 移除 networkd 的 wlan0 IP 配置（避免与 NM 抢 DHCP）"
rm -f /etc/systemd/network/20-wlan0.network
systemctl restart systemd-networkd 2>/dev/null || true

echo "==> 重启 NM 并连接"
systemctl restart NetworkManager
sleep 10
nmcli connection up oppo5g 2>&1 | tail -2
sleep 8

echo
echo "===== 验证 ====="
nmcli -t -f DEVICE,STATE,CONNECTION device status | grep wlan0
iw dev wlan0 link 2>/dev/null | grep -E "SSID|freq|rx bitrate"
ip -4 -br addr show wlan0

echo
echo "注意：图标恢复正常，但速度为 WPA3-SAE 水平（~45 Mbps）。"
echo "要恢复满速：重新执行 apply.sh"
