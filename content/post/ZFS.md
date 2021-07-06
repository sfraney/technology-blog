---
title: "Refamiliarizing with ZFS"
date: 2021-07-05
description: ""
summary: ""
draft: false
tags: []
---

## Introduction

Several years ago, I decided to implement my NAS using ZFS and I dutifully read all I could find, most notably everything by [Aaron Toponce](https://pthree.org/2012/04/17/install-zfs-on-debian-gnulinux/).  Since then, it's been mostly chugging along happily without much intervention by me, which means I've forgotten a lot of the details, particularly syntax, best practices, and caveats.

Now that I want to migrate my venerable server to my [all-in-one system](ref), I need to refresh my memory.  This post serves to collect a variety of details and outline a simple use-case for getting some practice before playing with my actual data.

## Misc. Thoughts

- With retirement of the server, I'll have an additional 1 TB disk that is currently hosting the root and home of the server as well as a 'temp' ZFS dataset.  Should I repurpose it as a hot spare or make RAIDZ-2?
  - I'm inclined to go with RAIDZ-2 as that significantly reduces my chance of losing data while waiting for a new disk
  - This [post](https://serverfault.com/questions/883065/zfs-hot-spares-versus-more-parity "ZFS hot spares versus more parity") (both the question and the top answer) have good reasoning behind going with RAIDZ-2 over a hot spare
  - Note **(add link to section discussing it)** I need to migrate the current dataset off of it first

- Enable compression (LZ4)
  - `zfs set compression=lz4 <pool>/<dataset>`

- Get automated snapshots working
  - Use my own script or ['zfs-auto-snapshot'](zfs-auto-snapshot)?  I initially used zfs-auto-snapshot when it was part of the PPA for ZFS but couldn't find it when I upgraded my system and ZFS was available as a proper package.  I _think_ the one in this repo is the right one and looks pretty straightforward.

- Setup weekly scrub

- "Set "autoexpand" to on, so you can expand the storage pool automatically after all disks in the pool have been replaced with larger ones. Default is off."

- Cache and SLOG
  - **Actually, I need to think through this:** according to ["best practices and caveats"](https://pthree.org/2012/12/13/zfs-administration-part-viii-zpool-best-practices-and-caveats/ "ZPool Best Practices and Caveats") "Do not share a SLOG or L2ARC DEVICE across pools. Each pool should have its own physical DEVICE, not logical drive, as is the case with some PCI-Express SSD cards. Use the full card for one pool, and a different physical card for another pool. If you share a physical device, you will create race conditions, and could end up with corrupted data."
  - Is this what I'm suggesting doing? I don't think so.  Assuming cache and SLOG aren't shared across pools _by default_ (which I'm pretty sure they're not; you specify them in creation of - or add them to - a specific pool), I'm not sharing cache and SLOG across 'tank' and 'temp' I'm just putting tank's cache and SLOG on the same disk as temp's data.  I think that's fine.
  - [cache](https://pthree.org/2012/12/07/zfs-administration-part-iv-the-adjustable-replacement-cache/ "The Adjustable Replacement Cache")
    - Create ~16GB partitions on each of the 3 SSDs to be striped as L2ARC
    - `zpool add tank cache /dev/disk/by-id/<first>...-partx /dev/disk/by-id/<second>...-partx /dev/disk/by-id/<third>...-partx`

  - [SLOG (ZIL)]()
    - Create ~2 GB partitions on each of the 3 SSDs to be mirrored for SLOG (a subset of which will be ZIL)
      - Per [blogger](https://pthree.org/2012/12/07/zfs-administration-part-iv-the-adjustable-replacement-cache/ "ZPool Best Practices and Caveats"), "1 GB is likely sufficient for your SLOG."  It would take _heavy_ workload to exercise even a 1 GB SLOG (it only holds transactions on their way to disk).
    - `zpool add tank log mirror /dev/disk/by-id/<first>...-party /dev/disk/by-id/<second>...-party /dev/disk/by-id/<third>...-party`

## Creating simple pool & dataset for migrating Windows 10 data

Just gonna create a pool of 1 disk.  I'm mainly just using ZFS to 1) refresh my memory of its use and 2) to leverage its simple SMB sharing properties (IIRC, you just mark a dataset as shared, in whatever way that is done, and then it's available on the network)

- Create storage pool: `zpool create win10 /dev/disk/by-id/ata-WDC_WD1600JS-75NCB1_WD-WCANM3331822`
- Create dataset: `zfs create -o casesensitivity=mixed win10/data`
  - `-o casesensitivity=mixed` ["because Microsoft Windows is not case sensitive"](https://wiki.debian.org/ZFS#CIFS_shares)
- [Share the dataset](https://wiki.debian.org/ZFS#CIFS_shares "ZFS CIFS shares"):
  `zfs set sharesmb=on win10/data`
  ~~~`zfs share win10/data`~~~ seemingly unnecessary: `cannot share 'win10/data': filesystem already shared`
- When done `zpool destroy win10`

## Migrating 'temp' pool

- Create striped pool of the remaining space on the 3 SSDs to create a new 'temp' pool
  - What is the SSD in the server currently doing? I know it's the L2ARC, but is it also the disk that contains root or is that the 1 TB disk?
- Export? the temp pool and Import? it to the new one?
  - ~~~Maybe take a read through [this post](https://pthree.org/2012/12/10/zfs-administration-part-v-exporting-and-importing-zpools/ "Exporting and Importing ZPools")~~~
  - Actually [this post](https://pthree.org/2012/12/20/zfs-administration-part-xiii-sending-and-receiving-filesystems/ "Sending and Receiving Filesystems") since I want to migrate live data.  This should also serve as a next step for 