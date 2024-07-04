---
title: "Replacing Disks in ZFS Pool"
date: 2024-07-04
description: "Time to upgrade my tank disks"
summary: ""
draft: false
tags: ["zfs", "server"]
---

I've had the 1TB disks in my ZFS pool for about 10 years now. If I recall correctly, I bought them during Black Friday sales in 2013 after getting back from an internship in Austin where I had gotten more familiar with ZFS as a hobby.

The disks seem to be doing fine today, but the storage isn't enough. I have been dumping data into them for the last 10 years without really worrying about capacity and now they're full. I have deleted a bunch of stuff that I don't need anymore, but I have snapshots that include the last 12 monthly snapshots, so I won't actually get that space back for up to a year. Since these disks are so old, I'd rather not risk losing important data by deleting older snapshots. The likelihood of having truly useful data only in those old snapshots is very low, but RAIDZ1 with 1TB is too small for today, anyway.

I found that 8TB seems to be the sweet spot for $/TB today, so I bought 3 WD Blue drives from the Western Digital store. They will replace the 1TB WD Green drives that I'm currently using. [^green]

## Process
From [Oracle](https://docs.oracle.com/cd/E19253-01/819-5461/gazgd/index.html) and [Reddit](https://www.reddit.com/r/zfs/comments/sqffah/replacing_drives_in_a_zpool/) it seems like I should do the following:

1. If possible, add both drives to the existing system with the drives-to-be-replaced.
   1. If I don't have enough SATA ports, replace one disk at a time
1. For each disk replaced: `sudo zpool replace tank ata-WDC_WD10EADS... <disk-by-id of new drive(s)>`
   1. I bought WD80EAAZ drives, so I expect the ID to be something like ata-*WD80EAAZ*
1. My tank zpool seems to already have the `autoexpand` property on, so once all drives are replaced, the size should grow to the full RAIDZ capacity of 3x8TB (~16 TB).

[^green]: I'm curious what happened with the Green drives