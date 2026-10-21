#!/bin/bash
set -e
K=/root/k619/linux-6.19.14
cd $K
# 生成 module.lds（KBUILD cmd_gen_lds 等价）
if [ ! -f scripts/module.lds ]; then
  aarch64-linux-gnu-gcc -E -P -UARCH -DLINKER -x assembler-with-cpp -nostdinc -I$K/arch/arm64/include -I$K/include -I$K/arch/arm64/include/uapi -I$K/include/uapi scripts/module.lds.S -o scripts/module.lds
  echo "module.lds generated"
fi
head -5 scripts/module.lds
cd drivers/soc/qcom
aarch64-linux-gnu-ld -r -T $K/scripts/module.lds -o rmtfs_mem.ko rmtfs_mem.o rmtfs_mem.mod.o
ls -la rmtfs_mem.ko
aarch64-linux-gnu-readelf -S rmtfs_mem.ko | grep -E 'this_module|modinfo'
cp rmtfs_mem.ko /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/
echo KO3_READY
