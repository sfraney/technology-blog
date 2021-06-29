---
title: "Initial Setup of Ryzen 9 5950x System"
date: 2021-06-28
description: ""
summary: ""
draft: false
tags: []
---

## Introduction

My 2 desktop systems are at least 7 years old and I figured it was time to upgrade them.  I want to do so by consolidating them - along with my home server (media, backup, misc. docker containers) - into 1 physical machine.  To do that, I've been eyeing a Ryzen 9 5950x.  It's probably overkill, but I wasn't inclined to cut any corners with this and consolidating 3 PCs into 1 - buying mobo, memory, 2 NVMe hard-drives, and the CPU -  still came in at right around $1,500.  Of course, with chip shortages and my outright refusal to buy from a scalper, I've been waiting patiently for about 8 months before, inexplicably, inventory seems to have suddenly become available.

I need to stage the process though, to keep minimize downtime (since I'd rather the rest of the house not be affected), avoid data loss, and get myself acquainted with some technology that I haven't thought much about for a while (e.g., ZFS).

## Steps

- Boot into existing hypervisor & guest OS
- Copy all of current boot disk to new nVME drive (which will hold Shari’s PC eventually) and wipe it
- Copy all of the next-best HDD (whichever that is) to backup and wipe it
  - This will be the disk for my hypervisor
    - Since I'm passing the graphics cards and NVMe drives through to the two GUI guests, I don't think the hypervisor needs to be performant
- Install hypervisor and new guest on newly-wiped HDD
  - Hypervisor - Ubuntu 20.04?
  - Guest - Arch Linux?
  - Update router address assignments (actually, it might not really matter when I do this)
    - Hypervisor will eventually be .201 (when it replaces the server)
- Setup current hypervisor docker services
  - Dropbox, Unifi Controller
  - Anything other than docker that it does that needs to be ported?
- Setup SSD RAIDZ-1 pool
  - Partially to make sure I get ZFS setup properly before importing existing pool
