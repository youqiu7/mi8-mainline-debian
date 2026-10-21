#!/bin/bash
set -e
rm -rf /root/a64libs /root/a64root /root/rmtfs-build
mkdir -p /root/a64libs /root/a64root
cd /root/a64root
S=/mnt/c/Users/duoya/AppData/Local/hermes/cache/scratch/qdebs
for d in libqrtr1_1.1-2%2bb1_arm64 libqrtr-dev_1.1-2%2bb1_arm64 libudev1_257.13-1~deb13u1_arm64 libudev-dev_257.13-1~deb13u1_arm64; do
  echo "== unpack $d"
  ar x "$S/$d.deb"
  tar -xf data.tar.xz || tar -xf data.tar.zst || tar -xf data.tar.gz || tar -xf data.tar
  rm -f control.tar.* debian-binary data.tar.*
done
cp -a /root/a64root/usr/lib/aarch64-linux-gnu/libqrtr.so* /root/a64libs/
cp -a /root/a64root/usr/lib/aarch64-linux-gnu/libudev.so* /root/a64libs/ 2>/dev/null || cp -a /root/a64root/lib/aarch64-linux-gnu/libudev.so* /root/a64libs/
cd /root/a64libs
ln -sf libqrtr.so.1 libqrtr.so
ln -sf libudev.so.1 libudev.so
ls -la
echo '== build rmtfs =='
cp -r /mnt/c/Users/duoya/AppData/Local/Temp/rmtfs-src /root/rmtfs-build
cd /root/rmtfs-build
touch qmi_rmtfs.c qmi_rmtfs.h
make clean > /dev/null 2>&1 || true
make CC=aarch64-linux-gnu-gcc CFLAGS='-Wall -g -O2' LDFLAGS='-L/root/a64libs -lqrtr -ludev -lpthread'
ls -la rmtfs
true
aarch64-linux-gnu-readelf -d rmtfs | grep NEEDED
cp rmtfs "$S/rmtfs-a64"
echo BUILD_DONE
