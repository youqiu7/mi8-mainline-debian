#!/usr/bin/env python
"""
mkdtbo.py —— 把 dtb 打包成 Android DTBO 镜像（ABL 从 dtbo 分区取 DTB 时用）

DTBO 格式（AOSP mkdtimg）:
  header  32B: magic 0xd7b7ab1e | total_size u32 | header_size=32 | entry_size=32
               | entry_count u32 | reserved[8] = 0
  entry   32B: dtb_size u32 | dtb_offset u32 | id u32 | rev u32 | custom[4]

Qualcomm ABL 用 (id, rev) 与设备的 qcom,board-id 匹配。
本机实测 board-id = <79 0> → id=79 rev=0。

用法:
  python mkdtbo.py --dtb foo.dtb --id 79 --rev 0 -o dtbo.img
  python mkdtbo.py --list dtbo.img            # 查看已有 dtbo 的条目
"""
import argparse, struct, sys

MAGIC = 0xd7b7ab1e
HDR = 32
ENT = 32


def align(n, a=4):
    return (n + a - 1) // a * a


def build(dtbs, out):
    count = len(dtbs)
    hdr_size = HDR
    data_start = hdr_size + ENT * count
    off = data_start
    entries = []
    blobs = b''
    for path, idv, rev in dtbs:
        d = open(path, 'rb').read()
        if d[:4] != b'\xd0\x0d\xfe\xed':
            raise SystemExit(f"{path} 不是合法 FDT")
        entries.append((len(d), off, idv, rev))
        blobs += d + b'\0' * (align(len(d)) - len(d))
        off += align(len(d))
    total = off
    img = struct.pack('<8I', MAGIC, total, hdr_size, ENT, count,
                      hdr_size, 0, 0)   # magic,total,hdr_size,entry_size,count,entries_offset,page_size,version
    for size, offset, idv, rev in entries:
        img += struct.pack('<4I', size, offset, idv, rev) + b'\0' * 16
    img += blobs
    open(out, 'wb').write(img)
    print(f"写入 {out}: {total} B, {count} 条")
    for size, offset, idv, rev in entries:
        print(f"  dtb_size={size:8d} offset={offset:9d} id={idv} rev={rev}")


def listing(path):
    d = open(path, 'rb').read()
    magic, total, hsz, esz, cnt = struct.unpack_from('<5I', d, 0)
    print(f"{path}: total={total} hdr={hsz} ent={esz} count={cnt} magic={magic:#x}")
    if magic != MAGIC:
        print("  ! 不是 DTBO 镜像")
        return
    for i in range(cnt):
        size, off, idv, rev = struct.unpack_from('<4I', d, hsz + i * esz)
        ok = d[off:off + 4] == b'\xd0\x0d\xfe\xed'
        print(f"  [{i}] size={size:8d} offset={off:9d} id={idv} rev={rev} FDT={'OK' if ok else 'BAD'}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dtb', action='append', default=[], help='可重复')
    ap.add_argument('--id', type=int, default=79)
    ap.add_argument('--rev', type=int, default=0)
    ap.add_argument('--list')
    ap.add_argument('-o', '--output', default='dtbo.img')
    a = ap.parse_args()
    if a.list:
        listing(a.list)
        return
    if not a.dtb:
        raise SystemExit("需要 --dtb")
    build([(p, a.id, a.rev) for p in a.dtb], a.output)


if __name__ == '__main__':
    main()
