#!/bin/bash
K=/root/k619/linux-6.19.14
python3 - << 'PYEOF'
p = "/root/k619/linux-6.19.14/drivers/soc/qcom/rmtfs_mem.c"
s = open(p).read()
if "0xf6301000ULL" in s:
    print("const fallback already in")
else:
    old = '''	} else if (!of_address_to_resource(node, 0, &res)) {
		dev_info(&pdev->dev, "rmtfs region from DT reg: %pr\\n", &res);
	} else {'''
    new = '''	} else {
		/* hard fallback: this board's rmtfs region (polaris dtb, fixed) */
		res.start = 0xf6301000ULL;
		res.end = 0xf6301000ULL + 0x200000 - 1;
		dev_info(&pdev->dev, "rmtfs region hardcoded: %pr\\n", &res);
	}
	if (resource_size(&res) == 0) {'''
    if old not in s:
        raise SystemExit("anchor missing")
    s = s.replace(old, new, 1)
    open(p, "w").write(s)
    print("hard fallback in")
PYEOF
cd $K || exit 1
rm -f drivers/soc/qcom/rmtfs_mem.o
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- KBUILD_EXTRA_CFLAGS=-DMODULE M=drivers/soc/qcom rmtfs_mem.o > /tmp/ko12.log 2>&1 || { grep error /tmp/ko12.log | head -4; exit 1; }
python3 /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/strip_modinfo.py > /dev/null
cd drivers/soc/qcom || exit 1
aarch64-linux-gnu-objcopy --globalize-symbol=qcom_rmtfs_mem_init --globalize-symbol=qcom_rmtfs_mem_exit rmtfs_mem.o
aarch64-linux-gnu-gcc -nostdinc -DKBUILD_MODNAME='"rmtfs_mem"' \
  -I$K/arch/arm64/include -I$K/arch/arm64/include/generated \
  -I$K/include -I$K/arch/arm64/include/uapi \
  -I$K/arch/arm64/include/generated/uapi -I$K/include/uapi \
  -I$K/include/generated/uapi \
  -include $K/include/linux/compiler-version.h \
  -include $K/include/linux/kconfig.h \
  -D__KERNEL__ -DMODULE -fno-strict-aliasing -fno-common -fshort-wchar \
  -std=gnu11 -fno-PIE \
  -c -o rmtfs_mem.mod.o rmtfs_mem.mod.c
aarch64-linux-gnu-ld -r -T $K/scripts/module.lds -o rmtfs_mem.ko rmtfs_mem.o rmtfs_mem.mod.o
cp rmtfs_mem.ko /mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs/
echo KO12_READY
