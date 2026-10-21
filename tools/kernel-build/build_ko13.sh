#!/bin/bash
K=/root/k619/linux-6.19.14
python3 - << 'PYEOF'
p = "/root/k619/linux-6.19.14/drivers/soc/qcom/rmtfs_mem.c"
s = open(p).read()
if "using default 1" in s:
    print("client-id fallback already in")
else:
    old = '''	ret = of_property_read_u32(node, "qcom,client-id", &client_id);
	if (ret) {
		dev_err(&pdev->dev, "failed to parse \\"qcom,client-id\\"\\n");
		return ret;

	}'''
    new = '''	ret = of_property_read_u32(node, "qcom,client-id", &client_id);
	if (ret) {
		dev_warn(&pdev->dev, "client-id parse failed (%d), using default 1\\n", ret);
		client_id = 1;
		ret = 0;
	}'''
    if old not in s:
        raise SystemExit("client-id anchor missing")
    s = s.replace(old, new, 1)
    open(p, "w").write(s)
    print("client-id fallback in")
PYEOF
# vmid 段宽松化（失败用 0xF = MSS_MSA）
python3 - << 'PYEOF'
p = "/root/k619/linux-6.19.14/drivers/soc/qcom/rmtfs_mem.c"
s = open(p).read()
if "using default MSS_MSA" in s:
    print("vmid fallback already in")
i = s.find('of_property_read_u32_array(node, "qcom,vmid"')
print("vmid ctx:", repr(s[i-120:i+320]) if i>=0 else "NOT FOUND")
PYEOF
cd $K || exit 1
rm -f drivers/soc/qcom/rmtfs_mem.o
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- KBUILD_EXTRA_CFLAGS=-DMODULE M=drivers/soc/qcom rmtfs_mem.o > /tmp/ko13.log 2>&1 || { grep error /tmp/ko13.log | head -4; exit 1; }
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
echo KO13_READY
