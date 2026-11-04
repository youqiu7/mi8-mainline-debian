#!/bin/bash
# ============================================================
# v95 WiFi 5G 定案应用脚本
#   Xiaomi Mi 8 (equuleus) / Debian 13 / Phosh
#   目标：5G 满速（WPA2-PSK + HT40），2.4G 兜底
#   前置：见 README.md 第 1 节「适用条件」
# ============================================================
set -e

[ "$(id -u)" -eq 0 ] || { echo "必须以 root 运行"; exit 1; }

DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP="/root/v95-wifi-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
echo "==> 备份到 $BACKUP"
cp -a /etc/systemd/network/ "$BACKUP/" 2>/dev/null || true
cp -a /etc/NetworkManager/conf.d/ "$BACKUP/" 2>/dev/null || true
cp -a /etc/wpa_supplicant/ "$BACKUP/" 2>/dev/null || true
cp -a /etc/systemd/logind.conf.d/ "$BACKUP/" 2>/dev/null || true

# ---------- 1. MAC 固定（udev .link）----------
echo "==> 1/6 安装 udev MAC 规则"
install -m 644 "$DIR/20-wlan0.link" /etc/systemd/network/20-wlan0.link
udevadm control --reload-rules

# ---------- 2. networkd 管 DHCP ----------
echo "==> 2/6 配置 networkd DHCP"
install -m 644 "$DIR/20-wlan0.network" /etc/systemd/network/20-wlan0.network

# ---------- 3. wpa_supplicant 配置（5G 优先）----------
echo "==> 3/6 配置 wpa_supplicant"
WPACONF=/etc/wpa_supplicant/wpa_supplicant-wlan0.conf
if [ -s "$WPACONF" ] && grep -q "OPPO A5-5G" "$WPACONF"; then
    echo "    已有 wpa 配置（含 OPPO A5-5G），保留不动"
else
    if [ -z "$WIFI_PASS" ]; then
        read -r -s -p "    请输入 WiFi 密码（OPPO A5 与 OPPO A5-5G 相同）: " WIFI_PASS
        echo
    fi
    [ -n "$WIFI_PASS" ] || { echo "密码为空，退出"; exit 1; }
    install -m 600 /dev/null "$WPACONF"
    cat > "$WPACONF" <<EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=CN

network={
    ssid="OPPO A5-5G"
    psk="$WIFI_PASS"
    priority=20
}

network={
    ssid="OPPO A5"
    psk="$WIFI_PASS"
    priority=10
}
EOF
    chmod 600 "$WPACONF"
    echo "    已生成 wpa 配置"
fi

# ---------- 4. logind 电源键交还 phosh ----------
echo "==> 4/6 修正 logind 电源键行为"
install -m 644 "$DIR/10-mi8-server.conf" /etc/systemd/logind.conf.d/10-mi8-server.conf

# ---------- 5. NM 放弃 wlan0 ----------
echo "==> 5/6 让 NM 不再管理 wlan0"
install -m 644 "$DIR/99-mi8-unmanaged.conf" /etc/NetworkManager/conf.d/99-mi8-unmanaged.conf
# 清掉可能冲突的实验配置
rm -f /etc/NetworkManager/conf.d/99-mi8-nm5g.conf
rm -f /etc/NetworkManager/conf.d/99-mi8-iwd.conf
systemctl disable --now iwd 2>/dev/null || true

# ---------- 6. 启用服务 ----------
echo "==> 6/7 启用并重启服务"
systemctl unmask wpa_supplicant@wlan0.service 2>/dev/null || true
systemctl enable wpa_supplicant@wlan0.service
systemctl restart NetworkManager
sleep 5
systemctl restart wpa_supplicant@wlan0.service
sleep 3
systemctl restart systemd-networkd
sleep 15

# ---------- 7. 刘海适配（Phosh 时钟避开 notch）----------
echo "==> 7/7 配置刘海感知（gmobile overlay）"
COMPAT=$(tr '\0' '\n' < /sys/firmware/devicetree/base/compatible 2>/dev/null | head -1)
echo "    设备 compatible: ${COMPAT:-unknown}"
mkdir -p /usr/share/gmobile-overlay
if [ -f "$DIR/xiaomi,polaris.json" ]; then
    install -m 644 "$DIR/xiaomi,polaris.json" "/usr/share/gmobile-overlay/xiaomi,polaris.json"
    install -m 644 "$DIR/50-gmobile-overlay.sh" /etc/profile.d/50-gmobile-overlay.sh
    echo "    已安装 notch 数据 + profile.d 钩子"
    echo "    注意：需要重新登录（或重启 gdm）才生效"
else
    echo "    跳过：未找到 xiaomi,polaris.json"
fi

# ---------- 验证 ----------
echo
echo "===== 验证 ====="
echo "--- supplicant 实例（必须只有 1 个）---"
pgrep -a wpa_supplicant | grep -- "-iwlan0" || echo "!! 未找到 wlan0 实例"
echo "--- 关联状态 ---"
iw dev wlan0 link 2>/dev/null | grep -E "SSID|freq|signal|rx bitrate" || echo "未关联"
echo "--- IP ---"
ip -4 -br addr show wlan0
echo "--- 连通性 ---"
curl -s -m 8 -o /dev/null -w "baidu=%{http_code} t=%{time_total}s\n" http://www.baidu.com || echo "curl 失败"

echo
echo "完成。若速度低于 100 Mbps，等 20 秒让速率自适应后再测。"
echo "回滚：bash $DIR/rollback.sh"
