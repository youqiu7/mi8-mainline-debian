#!/bin/bash
# 备份 equuleus 关键分区（只读操作：dd 读分区 -> /sdcard -> adb pull -> 删除临时文件）
# 用法: bash 02-工具/backup_partitions.sh
set -u

PT="F:/小米刷机/dagu移植debian/new-chat-1/platform-tools/platform-tools"
BK="F:/小米刷机/米8移植debian/03-备份"
SER="225bd9ea"
mkdir -p "$BK"

# 第一个参数为 true 时不删除设备上的临时文件（便于排查）
KEEP="${1:-false}"

PARTS="recovery misc devinfo splash logo dtbo vbmeta persist frp \
abl_a abl_b xbl_a xbl_b tz_a tz_b hyp_a hyp_b devcfg_a devcfg_b \
keymaster_a keymaster_b cmnlib64_a cmnlib64_b storsec_a storsec_b qupfw_a qupfw_b aop_a aop_b modem"

echo "== 设备当前状态 =="
"$PT/adb.exe" -s "$SER" get-state || { echo "设备未连接，中止"; exit 1; }

for p in $PARTS; do
  tmp="/sdcard/bk_${p}.img"
  printf "%-14s " "$p"
  out=$("$PT/adb.exe" -s "$SER" shell "su -c 'dd if=/dev/block/by-name/$p of=$tmp bs=1M 2>&1; md5sum $tmp'" 2>&1 | tr -d '\r')
  size=$(echo "$out" | grep -oE '[0-9]+ bytes' | head -1)
  md5=$(echo "$out" | grep -oE '^[0-9a-f]{32}' | head -1)
  if [ -z "$md5" ]; then echo "失败的：$out"; continue; fi
  "$PT/adb.exe" -s "$SER" pull "$tmp" "$BK/bk_${p}.img" >/dev/null 2>&1
  if [ "$KEEP" != "true" ]; then
    "$PT/adb.exe" -s "$SER" shell "su -c 'rm -f $tmp'" >/dev/null 2>&1
  fi
  echo "${size:-?}  md5=$md5"
done

echo
echo "== 本地文件校验 =="
cd "$BK" && md5sum bk_*.img > md5-$(date +%Y%m%d).txt
ls -l "$BK" | tail -5
echo "清单: $BK/md5-$(date +%Y%m%d).txt"
