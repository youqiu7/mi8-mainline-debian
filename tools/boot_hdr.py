#!/usr/bin/env python
"""解析 Android boot.img (v0/v1/v2) 与 dtbo.img 头部，只读分析用。"""
import struct, sys, os

def parse_boot(path):
    d = open(path, 'rb').read()
    magic = d[:8]
    print(f"[boot] {path}  size={len(d)}  magic={magic!r}")
    if magic != b'ANDROID!':
        print("  非 Android boot 镜像"); return
    (kernel_size, kernel_addr, ramdisk_size, ramdisk_addr,
     second_size, second_addr, tags_addr, page_size,
     header_version, os_version) = struct.unpack_from('<10I', d, 8)
    hdr = {8+4*i: v for i, v in enumerate(
        [kernel_size, kernel_addr, ramdisk_size, ramdisk_addr,
         second_size, second_addr, tags_addr, page_size,
         header_version, os_version])}
    name = d[48:64].split(b'\0')[0]
    cmdline = d[64:64+512].split(b'\0')[0]
    id_ = d[576:576+32].hex()
    extra = d[608:608+1024]
    print(f"  kernel_size={kernel_size} (0x{kernel_size:x}) @0x{kernel_addr:x}")
    print(f"  ramdisk_size={ramdisk_size} (0x{ramdisk_size:x}) @0x{ramdisk_addr:x}")
    print(f"  second_size={second_size} @0x{second_addr:x}")
    print(f"  tags_addr=0x{tags_addr:x}  page_size={page_size}  header_version={header_version}")
    print(f"  os_version=0x{os_version:08x}  name={name!r}")
    print(f"  cmdline={cmdline.decode('utf-8','replace')}")
    print(f"  id={id_}")
    if header_version >= 2:
        recov_dtbo_size, recov_dtbo_offset = struct.unpack_from('<II', d, 1632)
        dtb_size, dtb_addr = struct.unpack_from('<IQ', d, 1648)
        print(f"  recovery_dtbo_size={recov_dtbo_size} offset={recov_dtbo_offset}")
        print(f"  dtb_size={dtb_size} dtb_addr=0x{dtb_addr:x}")
    # page-aligned layout check
    def pages(n):
        return (n + page_size - 1) // page_size * page_size
    off = page_size
    print(f"  kernel @ {off} ... {off+pages(kernel_size)}")
    off += pages(kernel_size)
    print(f"  ramdisk @ {off} ... {off+pages(ramdisk_size)}")
    off += pages(ramdisk_size)
    if second_size:
        print(f"  second @ {off}")
        off += pages(second_size)
    if header_version >= 2:
        print(f"  recovery_dtbo @ {off}")
        off += pages(recov_dtbo_size)
    print(f"  计算负载总长 = {off} 字节")
    # scan for FDT magic after payload
    fdt = d.find(b'\xd0\x0d\xfe\xed', off)
    print(f"  首个 FDT magic 位置(>=payload_end): {fdt}")
    # kernel 头部特征
    k = d[page_size:page_size+64]
    print(f"  kernel 头 64B: {k.hex()}")
    if k[0x38:0x3c] == b'ARMd':
        print("  ARM64 Image magic 'ARMd' OK")
    # 是否含 gzip/xz
    if k[:2] == b'\x1f\x8b': print("  kernel 是 gzip 压缩")
    elif k[:6] == b'\xfd7zXZ\x00': print("  kernel 是 xz 压缩")

def parse_dtbo(path):
    d = open(path, 'rb').read()
    magic = d[:4]
    total, hdr_size, entry_size, entry_count = struct.unpack_from('<4I', d, 4)
    print(f"[dtbo] {path} size={len(d)} magic={magic!r} total={total} hdr_size={hdr_size} entry_size={entry_size} count={entry_count}")
    off = hdr_size
    for i in range(entry_count):
        size, offset, id_, rev = struct.unpack_from('<4I', d, off + i*entry_size)
        # 找对应 FDT
        p = offset if offset else None
        tag = ''
        if p and p+4 <= len(d) and d[p:p+4] == b'\xd0\x0d\xfe\xed':
            tag = 'FDT-OK'
        print(f"  [{i}] size={size:8d} offset={offset:9d} id={id_} rev={rev} {tag}")

for p in sys.argv[1:]:
    if os.path.basename(p).startswith('dtbo') or p.endswith('.dtbo'):
        parse_dtbo(p)
    else:
        parse_boot(p)
