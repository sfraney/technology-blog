---
title: "Performance Tuning Virtual Machines"
date: 2021-07-15
description: ""
summary: ""
draft: false
tags: []
---

I wanted to hold off on the performance tuning until I got things functional and maybe got a feel for the performance characteristics so I wasn't messing with things that didn't matter.  It turns out that, while the Linux guest is running like a champ, the Windows guest is a little grumpy.  It could be due to different usecases more than OSs, though; the specific scenario where Windows was acting up was during a Zoom call when a bunch of Chrome tabs were being restored (and there appears to be a virus issue on thing to boot...).

## To Do

In order of priority
1. Pin CPUs
1. Enable 1G huge pages
1. Figure out what memballoon is and deal with it appropriately

## Huge Pages

This seemed like the first thing to take a look at.  I know how address translation works and huge pages are a no brainer for virtual machines.  According to the [Arch Wiki](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Huge_memory_pages "Huge memory pages"), it's such a no-brainer that QEMU does it by default (at least using 2M pages).  Further, since my VMs get autostarted at boot, there's no real fragmentation to worry about that might limit the number of huge pages available to the guests when they launch.  Indeed, looking at the suggested maps (`grep -P 'AnonHugePages:\s+(?!0)\d+' /proc/[QEMU Guest PID]/smaps`) indicates that all the memory for both guests is backed by huge pages.

There might be some opportunity with larger pages (1G), but this might not be the first thing to tweak.

## CPU Pinning

This felt like more of an ignorant no-brainer.  In other words, it _sounds_ like it's a good idea to folks not particularly familiar with CPU architecture, but to me, it seems marginal.  Again, after reading the [Arch Wiki](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#CPU_pinning "CPU pinning"), I'm wondering if there might be more to it.  Assuming a guest process could get scheduled on any core when it's woken, I can see how cache thrash _could_ be a problem, but then again, how much of that process's data is still in the cache anyway since it was last scheduled?  I'll at least give it a try and see what comes of it.  It seems simple enough and maybe it would be good for the hypervisor (who I'm not exactly leaving idle), to have some dedicated cores for it.

### Process

- Pin set of CPUs to guests
  - Ensure all threads (just 2 for SMT2) for a core are pinned together
  - Pin groups that share the same cache levels (probably just LLC given prevalence of private caches at lower levels)
    - See groupings via `lscpu -e`
- Prevent the host from using pinned CPUs via [isolation of pinned CPUs](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Isolating_pinned_CPUs "Isolating pinned CPUs")

## Disable memballoon

I seem to recall seeing a blogger - or maybe a Red Hat or other OS guide - mention that memballoon is bad and should just be disabled.

**TODO:** figure out what memballoon is and deal with it appropriately

## Networking

This wasn't something I considered until realizing Zoom meetings on the Windows guest get really choppy when the browser is loading pages => maybe the virtualized NIC is having problems.

**TODO:** try to verify that there's a network problem (e.g., speed test)
  - Got 95% of max download BW and 85% of max upload BW on Linux guest
    - Notably, this was done during a Zoom meeting on the Windows guest => the issue may not be the network but something about Chrome and Zoom interactions
      - Further, issues _did_ crop up a few minutes later when the Windows PC opened a new tab => seems very likely that the problem is not specifically network related.  Maybe interrupts or something like that.
      - [Tweak Zoom settings?](https://www.digitaltrends.com/computing/common-problems-with-zoom-and-how-to-fix-them/)
      	- "Try unchecking the HD and Touch Up My Appearance options. To access these options, click the cog icon (Settings) on the main screen of the Zoom desktop app, or click the arrow icon within the video camera icon during a call and then select Video Settings on the pop-up menu. After that, select the Video category listed on the left (if it isn’t already selected)."

**TODO:** look into options for improving network performance
