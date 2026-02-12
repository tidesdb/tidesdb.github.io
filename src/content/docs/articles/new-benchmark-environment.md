---
title: "New Benchmark Environment"
description: "Article on TidesDB new benchmark environment"
head:
  - tag: meta
    attrs:
      property: og:image
      content: https://tidesdb.com/Hetzner_DCP_Luftbild.jpg
  - tag: meta
    attrs:
      name: twitter:image
      content: https://tidesdb.com/Hetzner_DCP_Luftbild.jpg
---

<div class="article-image">

![New Benchmark Environment](/Hetzner_DCP_Luftbild.jpg)

</div>

*by <a href="https://alexpadula.com">Alex Gaetano Padula</a>*

*published on February 12th, 2026*

Well, I've been wanting to get a good dedicated server for a while now.  I finally got around to it.  I chose go to go with <a href="https://www.hetzner.com">Hetzner</a>.  

This is what I ended up getting purely for benchmarking and analysis:
![new benchmark environment](/hetz-server-spec.png)

The prices are great, for just over $100 CAD per month you can get above from the <a href="https://www.hetzner.com/sb/">server auctions</a>.


![specs](/sspec1.png)

I ended up creating custom installimage and post-install scripts for the server as I wanted it to be setup a certain way for effective benchmarking, to really push storage engines.

I placed the files below in `/tmp` on the server.

**setup.conf**

```bash
DRIVE1 /dev/nvme0n1

SWRAID 0

BOOTLOADER grub
HOSTNAME xfs
PART swap  swap   4G
PART /boot ext4   1G
PART /     xfs    all
IMAGE /root/images/Ubuntu-2204-jammy-amd64-base.tar.gz
```

**post-install.sh**
```bash
#!/usr/bin/env bash
set -euo pipefail

echo "== Post-install: packages =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  xfsprogs nvme-cli fio locales

echo "== Post-install: locale fix (prevents LC_* warnings) =="
sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen || true
locale-gen
update-locale LANG=en_US.UTF-8

echo "== Post-install: fstab mount options for XFS (LSM-optimized) =="
ROOT_SRC="$(findmnt -no SOURCE / || true)"
ROOT_UUID="$(blkid -s UUID -o value "${ROOT_SRC}" 2>/dev/null || true)"

if [[ -n "${ROOT_UUID}" ]]; then
  # noatime         -- skip access time updates (reduces write amplification)
  # nodiratime      -- skip dir access time
  # discard         -- enable TRIM for SSD (matches RocksDB benchmark setup)
  # inode64         -- allow inodes anywhere on disk
  # logbufs=8       -- more log buffers for write-heavy workloads
  # logbsize=256k   -- larger log buffer size
  XFS_OPTS="defaults,noatime,nodiratime,discard,inode64,logbufs=8,logbsize=256k"

  awk -v uuid="${ROOT_UUID}" -v opts="${XFS_OPTS}" '
    $2=="/" {print "UUID="uuid" / xfs "opts" 0 1"; next}
    {print}
  ' /etc/fstab > /etc/fstab.new && mv /etc/fstab.new /etc/fstab
fi

echo "== Post-install: enable continuous TRIM =="
systemctl enable --now fstrim.timer || true

echo "== Post-install: I/O scheduler (none for NVMe) =="
for dev in /sys/block/nvme*/queue/scheduler; do
  echo "none" > "$dev" 2>/dev/null || true
done

echo "== Post-install: sysctl tuning for LSM workloads =="
cat >> /etc/sysctl.d/99-lsm-bench.conf << 'EOF'
# Reduce swappiness for in-memory workloads
vm.swappiness = 1
# Increase dirty ratio for write batching
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10
# Reduce vfs_cache_pressure
vm.vfs_cache_pressure = 50
EOF
sysctl --system

echo "== Post-install: setup dedicated data drive (nvme1n1) =="
DATA_DEV="/dev/nvme1n1"
if [[ -b "${DATA_DEV}" ]]; then
  # We wipe and create single partition
  wipefs -af "${DATA_DEV}"
  parted -s "${DATA_DEV}" mklabel gpt
  parted -s "${DATA_DEV}" mkpart primary 0% 100%
  
  # We format as XFS with LSM-optimized settings
  mkfs.xfs -f -K "${DATA_DEV}p1"
  
  # We get UUID and add to fstab
  DATA_UUID="$(blkid -s UUID -o value "${DATA_DEV}p1")"
  mkdir -p /data
  DATA_OPTS="defaults,noatime,nodiratime,discard,inode64,logbufs=8,logbsize=256k"
  echo "UUID=${DATA_UUID} /data xfs ${DATA_OPTS} 0 2" >> /etc/fstab
  mount /data
  
  echo "Data drive mounted at /data"
fi

echo "== Post-install: initramfs refresh =="
apt-get install -y --no-install-recommends initramfs-tools
update-initramfs -u -k all

echo "== Post-install done =="
```


**Stop and wipe existing RAID (run in rescue mode)** this is required by Hetzner.

```bash
mdadm --stop /dev/md0 2>/dev/null || true
mdadm --stop /dev/md1 2>/dev/null || true
mdadm --stop /dev/md2 2>/dev/null || true
mdadm --zero-superblock /dev/nvme0n1p1 2>/dev/null || true
mdadm --zero-superblock /dev/nvme0n1p2 2>/dev/null || true
mdadm --zero-superblock /dev/nvme0n1p3 2>/dev/null || true
mdadm --zero-superblock /dev/nvme1n1p1 2>/dev/null || true
mdadm --zero-superblock /dev/nvme1n1p2 2>/dev/null || true
mdadm --zero-superblock /dev/nvme1n1p3 2>/dev/null || true
wipefs -af /dev/nvme0n1
wipefs -af /dev/nvme1n1
```

I basically in rescue mode setup the server with this one command after setting up scripts:
```bash
chmod +x /tmp/post-install.sh
installimage -a -c /tmp/setup.conf -x /tmp/post-install.sh
```

![all setup](/setup-hetz.png)

After that I rebooted the server and it was ready to go.

With that, I think this was a great investment, and I will be expanding more in the future.  For now this server will be used in upcoming analysis.

Look out!!

*Thanks for reading!*

--