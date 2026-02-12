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

**setup.cnf**

Ubuntu 22.04 (Jammy), RAID1 over two NVMe, XFS root.

```bash
DRIVE1 /dev/nvme0n1
DRIVE2 /dev/nvme1n1

SWRAID 1
SWRAIDLEVEL 1

BOOTLOADER grub
HOSTNAME xfs

# ---- Partitions ----
# swap on RAID1
PART swap  swap   4G
# /boot on RAID1 (ext4)
PART /boot ext4   1G
# root on RAID1 (XFS) - "all remaining space"
PART /     xfs    all

# ---- OS image ----
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
  xfsprogs nvme-cli mdadm locales

echo "== Post-install: locale fix (prevents LC_* warnings) =="
sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen || true
locale-gen
update-locale LANG=en_US.UTF-8

echo "== Post-install: ensure mdadm config present =="
mkdir -p /etc/mdadm
mdadm --detail --scan > /etc/mdadm/mdadm.conf || true

echo "== Post-install: fstab mount options for XFS root =="
ROOT_SRC="$(findmnt -no SOURCE / || true)"
ROOT_UUID="$(blkid -s UUID -o value "${ROOT_SRC}" 2>/dev/null || true)"

if [[ -n "${ROOT_UUID}" ]]; then
  # We prefer scheduled TRIM via fstrim.timer (recommended for SSD/NVMe).
  # Essentially like discard option in which Meta team uses.
  XFS_OPTS="defaults,noatime,nodiratime,inode64"

  awk -v uuid="${ROOT_UUID}" -v opts="${XFS_OPTS}" '
    $2=="/" {print "UUID="uuid" / xfs "opts" 0 1"; next}
    {print}
  ' /etc/fstab > /etc/fstab.new && mv /etc/fstab.new /etc/fstab
fi

echo "== Post-install: enable periodic TRIM =="
systemctl enable --now fstrim.timer || true

echo "== Post-install: initramfs refresh (picks up mdadm etc.) =="
apt-get install -y --no-install-recommends initramfs-tools
update-initramfs -u -k all

echo "== Post-install done =="
```

I basically on rescue mode setup the server with this one command:
```bash
installimage -a -c /tmp/setup.conf -x /tmp/post-install.sh
```

![all setup](/setup-hetz.png)
![final specs](/sspec2.png)

After that I rebooted the server and it was ready to go.

With that, I think this was a great investment, and I will be expanding more in the future.  For now this server will be used in upcoming analysis.

Look out!!

*Thanks for reading!*

--