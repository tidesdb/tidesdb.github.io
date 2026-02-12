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
# Note: Not using set -e because some commands fail in chroot but are non-fatal
set -uo pipefail

echo "== Post-install: packages =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  xfsprogs nvme-cli fio locales parted

echo "== Post-install: locale fix (prevents LC_* warnings) =="
sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen || true
locale-gen
update-locale LANG=en_US.UTF-8

echo "== Post-install: fstab mount options for XFS (LSM-optimized) =="
# In chroot, findmnt doesn't work reliably. Parse fstab directly.
XFS_OPTS="defaults,noatime,nodiratime,discard,inode64,logbufs=8,logbsize=256k"
# noatime         -- skip access time updates (reduces write amplification)
# nodiratime      -- skip dir access time
# discard         -- enable TRIM for SSD (matches RocksDB benchmark setup)
# inode64         -- allow inodes anywhere on disk
# logbufs=8       -- more log buffers for write-heavy workloads
# logbsize=256k   -- larger log buffer size

# Update XFS root mount options in fstab
if grep -q 'xfs' /etc/fstab; then
  sed -i 's|^\(UUID=[^ ]*\s\+/\s\+xfs\s\+\)[^ ]*|\1'"${XFS_OPTS}"'|' /etc/fstab
  echo "Updated /etc/fstab with XFS options: ${XFS_OPTS}"
  cat /etc/fstab
fi

echo "== Post-install: enable TRIM timer (will activate on boot) =="
systemctl enable fstrim.timer 2>/dev/null || true

echo "== Post-install: I/O scheduler udev rule (applies on boot) =="
cat > /etc/udev/rules.d/60-nvme-scheduler.rules << 'EOF'
# Set I/O scheduler to none for NVMe devices
ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/scheduler}="none"
EOF

echo "== Post-install: sysctl tuning for LSM workloads =="
cat > /etc/sysctl.d/99-lsm-bench.conf << 'EOF'
# Reduce swappiness for in-memory workloads
vm.swappiness = 1
# Increase dirty ratio for write batching
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10
# Reduce vfs_cache_pressure
vm.vfs_cache_pressure = 50
EOF

echo "== Post-install: first-boot systemd service to setup data drive =="
# Create a systemd service (more reliable than rc.local on Ubuntu 22.04)
cat > /etc/systemd/system/setup-data-drive.service << 'SVCEOF'
[Unit]
Description=One-time setup of data drive
After=local-fs.target
ConditionPathExists=!/data/.setup-complete

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-data-drive.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVCEOF

cat > /usr/local/bin/setup-data-drive.sh << 'SCRIPTEOF'
#!/bin/bash
set -x
DATA_DEV="/dev/nvme1n1"
DATA_OPTS="defaults,noatime,nodiratime,discard,inode64,logbufs=8,logbsize=256k"

if [[ ! -b "${DATA_DEV}" ]]; then
  echo "Data device ${DATA_DEV} not found, skipping"
  exit 0
fi

if mountpoint -q /data; then
  echo "/data already mounted, skipping"
  exit 0
fi

echo "Setting up ${DATA_DEV} as /data..."
wipefs -af "${DATA_DEV}"
parted -s "${DATA_DEV}" mklabel gpt
parted -s "${DATA_DEV}" mkpart primary 0% 100%
partprobe "${DATA_DEV}"
sleep 3  # Wait for kernel to create partition device

# Handle both nvme0n1p1 and nvme0n1-part1 naming conventions
if [[ -b "${DATA_DEV}p1" ]]; then
  PART="${DATA_DEV}p1"
elif [[ -b "${DATA_DEV}-part1" ]]; then
  PART="${DATA_DEV}-part1"
else
  echo "ERROR: Partition device not found"
  ls -la /dev/nvme*
  exit 1
fi

mkfs.xfs -f -K "${PART}"
DATA_UUID="$(blkid -s UUID -o value "${PART}")"
mkdir -p /data
echo "UUID=${DATA_UUID} /data xfs ${DATA_OPTS} 0 2" >> /etc/fstab
mount /data
touch /data/.setup-complete
echo "Data drive setup complete: /data on ${PART} (UUID=${DATA_UUID})"
SCRIPTEOF
chmod +x /usr/local/bin/setup-data-drive.sh

systemctl enable setup-data-drive.service 2>/dev/null || true

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

On first boot:
- XFS root will have optimized mount options
- I/O scheduler will be set to none via udev
- sysctl tuning will be applied
- First boot: systemd service will format nvme1n1 and mount /data

With that, I think this was a great investment, and I will be expanding more in the future.  For now this server will be used in upcoming analysis.

Look out!!

*Thanks for reading!*

--

Logs from my setup:

| File | Checksum |
|------|----------|
| [postinstall_debug.txt](/hetz-setup-logs/postinstall_debug.txt) | `21649b46654bdcd80964b3577fbc5280faccd0b05f48f2deb6acf1c1119004a3` |
| [debug.txt](/hetz-setup-logs/debug.txt) | `8ab8fb219f0b9b5d5ae3aed4084c6c9ecbcd52d7303bdd97d9ca92c370719747` |