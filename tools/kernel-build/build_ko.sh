#!/bin/bash
set -e
cd /root/k619/linux-6.19.14
cp /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/config-48.gz /tmp/c48.gz
zcat /tmp/c48.gz > .config
make ARCH=arm64 olddefconfig > /dev/null 2>&1
echo '=== 关键配置确认 ==='
grep -E 'CONFIG_QCOM_RMTFS_MEM|CONFIG_QCOM_SCM|CONFIG_MODVERSIONS|CONFIG_PREEMPT=|CONFIG_STRICT_DEVMEM' .config
echo '=== 编译 qcom_rmtfs_mem.ko ==='
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- M=drivers/soc/qcom qcom_rmtfs_mem.ko 2>&1 | tail -5
ls -la drivers/soc/qcom/qcom_rmtfs_mem.ko
aarch64-linux-gnu-modinfo drivers/soc/qcom/qcom_rmtfs_mem.ko 2>/dev/null | grep -E 'vermagic|depends' || aarch64-linux-gnu-readelf -p .modinfo drivers/soc/qcom/qcom_rmtfs_mem.ko | grep -E 'vermagic|depends'
cp drivers/soc/qcom/qcom_rMTFS.ko /dev/null 2>/dev/null || cp drivers/soc/qcom/qcom_rmtfs_mem.ko /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/
echo KO_READY
