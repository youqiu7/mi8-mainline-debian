#!/bin/bash
cd /root/k619/linux-6.19.14 || exit 1
SRC=drivers/soc/qcom/rmtfs_mem.c
echo '=== MODULE_LICENSE 现状 ==='
grep -n 'MODULE_' $SRC || echo 'NO MODULE MACROS'
# 若缺失则补上（末尾追加）
if ! grep -q 'MODULE_LICENSE' $SRC; then
  printf '\nMODULE_LICENSE("GPL");\nMODULE_DESCRIPTION("Qualcomm Remote Filesystem memory driver");\n' >> $SRC
  echo 'PATCHED: added MODULE_LICENSE'
fi
rm -f drivers/soc/qcom/rmtfs_mem.o drivers/soc/qcom/rmtfs_mem.mod*
echo '=== 重编（WARN 模式绕过 Module.symvers 缺失）==='
KBUILD_MODPOST_WARN=1 make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- M=drivers/soc/qcom rmtfs_mem.ko 2>&1 | grep -E 'CC|LD|MODPOST|ERROR|error' | head -10
ls -la drivers/soc/qcom/rmtfs_mem.ko && echo KO_BUILT
cp drivers/soc/qcom/rmtfs_mem.ko /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/ && echo KO_COPIED
