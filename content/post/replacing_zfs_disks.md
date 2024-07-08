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

## Problem

I received the following error when I tried to run `sudo zpool replace tank ata-WDC_WD10EADS... ata-WDC_WD80EAAZ...` after adding one of the new disks:

`cannot replace ata-WDC_WD10EADS... with ata-WDC_WD80EAAZ...: new device has a different optimal sector size; use the option '-o ashift=N' to override the optimal size`

My original drives have sector sizes of 512 bytes. This apparently led to the pool being created with ashift of 9 (log~2~(512)). The new drives have sector size of 4096 bytes. By adding them to the existing zpool, I will need to make them use ashift of 9 rather than their default of 12 (via `-o ashift=9` to the `replace` commmand, I imagine). This sounds very bad.

I think I'll go back to my initial plan of recovering from backup. The minor problem is that the pool name may have to be different. This will change mount points and such. I know that mapped drives on other machines will have to change their names. That's not a big deal, but I'm worried about what else might need to be changed that I'm not aware of.

References:

- https://github.com/openzfs/zfs/issues/6975
- https://github.com/openzfs/zfs/pull/2427#issuecomment-321887912
- https://askubuntu.com/q/1102315
- https://unix.stackexchange.com/q/90121

## Try #2

I will try to run a manual backup of my current pool utilizing some info from my [Offsite Backup post]({{< ref "offsite_backup" >}}). I will then create a new pool with the new drives and recover the data from the offsite backup.

*I NEED TO REVIEW MY OFFSITE BACKUP PROCESS TO REMEMBER HOW TO RECOVER*

1. I think today (7/8/2024) is coincidentally the day that my monthly backup will happen at 6 PM => wait until that completes.
1. Export the current pool, changing its name if possible `zpool export tank <new name>`
   1. The [Oracle documentation](https://docs.oracle.com/en/operating-systems/solaris/oracle-solaris/11.4/manage-zfs/importing-zfs-storage-pools.html) says "You can only change the name of a pool while *exporting* and importing the pool..." (emphasis mine), but I don't see any option to `export` to change the name, so I might have to export, then import with a new name just to change the name.
1. If I had to do export/import in the sub-bullet above, I may have to destroy the existing "tank" pool.
1. Physically replace old drives with new drives
1. Create new "tank" pool with new drives
1. Import backed up data from AWS:
   1. Unfreeze old sets
   1. `zfs receive` them in chronological order

[^green]: I'm curious what happened with the Green drives