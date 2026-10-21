#!/bin/bash
K=/root/k619/linux-6.19.14
python3 - << 'PYEOF'
p = "/root/k619/linux-6.19.14/drivers/soc/qcom/rmtfs_mem.c"
s = open(p).read()
if "this board: VMID mapping is fixed" in s:
    print("vmid patch already in")
else:
    i = s.find('	num_vmids = of_property_count_u32_elems(node, "qcom,vmid");')
    j = s.find('	dev_set_drvdata(&pdev->dev, rmtfs_mem);')
    if i < 0 or j < 0 or j <= i:
        raise SystemExit("anchors missing %d %d" % (i, j))
    new = '''	/* this board: VMID mapping is fixed (HLOS + MSS_MSA); skip DT parsing
	 * (of property reads unreliable on this reserved-memory child) */
	num_vmids = 1;
	vmid[0] = QCOM_SCM_VMID_MSS_MSA;

	if (!qcom_scm_is_available()) {
		dev_warn(&pdev->dev, "SCM unavailable, skipping mem assign\\n");
	} else {
		perms[0].vmid = QCOM_SCM_VMID_HLOS;
		perms[0].perm = QCOM_SCM_PERM_RW;
		perms[1].vmid = vmid[0];
		perms[1].perm = QCOM_SCM_PERM_RW;

		rmtfs_mem->perms = BIT(QCOM_SCM_VMID_HLOS);
		ret = qcom_scm_assign_mem(rmtfs_mem->addr, rmtfs_mem->size,
					  &rmtfs_mem->perms, perms, num_vmids + 1);
		if (ret < 0)
			dev_warn(&pdev->dev, "assign memory failed (%d), continuing\\n", ret);
		ret = 0;
	}

'''
    s = s[:i] + new + s[j:]
    open(p, "w").write(s)
    print("vmid section replaced")
PYEOF
cd $K || exit 1
rm -f drivers/soc/qcom/rmtfs_mem.o
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- KBUILD_EXTRA_CFLAGS=-DMODULE M=drivers/soc/qcom rmtfs_mem.o > /tmp/ko14.log 2>&1 || { grep -E 'error' /tmp/ko14.log | head -4; exit 1; }
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
echo KO14_READY
