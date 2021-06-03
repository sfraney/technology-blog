---
title: "Creating Virtual Machine from rsync Backup to Image"
description: ""
summary: ""
date: 2021-06-01T23:33:00+07:00
draft: false
time: ""
tags: ["kvm"]
featured_image: 
---

## Purpose

Create virtual machine that is as accurate of a model of a live system (e.g., a  [router]({{< ref "arch_router" >}}) as possible in order to verify updates (e.g., `pacman -Syu`) and new software (e.g., VPN).

## Process

### Create disk image from backup directory (created weekly with rsync)
From [https://serverfault.com/a/247933](https://serverfault.com/a/247933 "ServerFault Answer")

From directory containing the 'latest' backup
1. Create empty image: `dd if=/dev/null of=archrouter.img bs=4M seek=2048`
1. Create filesystem on the image: `mkfs.ext4 -F archrouter.img`
1. Mount the image: `sudo mount -t ext4 -o loop archrouter.img /mnt/tmp`
1. Copy backup to mounted image: `sudo rsync -azvH latest/ /mnt/tmp/`
1. Unmount: `sudo umount /mnt/tmp`
1. Fix permissions (heavy handed, will probably have to tweak some when VM is live
   - `sudo chown -R root:root /mnt/tmp/`
   - `sudo chown -R 1000:1000 /mnt/tmp/home/admin` (since `admin`'s group is 1000)
1. Convert to qcow2 (to avoid taking up more disk space than necessary; this could be skipped and just create the VM from the .img): `qemu-img convert -O qcow2 /mnt/backup/archrouter.backup/archrouter.img /mnt/backup/archrouter.backup/archrouter.qcow2`

- Somehow, this process took my 1.6G directory and created a 2.3G image.  Something is clearly wrong with the process that I should probably track down.  Note, despite making what I think should be a 2G image with dd, the resulting image after rsync is 8G.  Maybe the problem is somewhere around there.

### Creating KVM virtual machine

'permission denied' error required uncommenting and changing `user = "root"` to `user = "<my user>"` in /etc/libvirt/qemu.conf

`virt-install --name archrouter --memory 2048 --vcpus 2 --cpu host-passthrough --disk path=/media/sean/archrouter.qcow2,format=qcow2 --import --network none`
**Do not provide network to the VM on initial spin up in case there are issues**
- Note, no networking: since this is a router, there are potential issues, though I don't expect them since no one will be connected to it.  Plus, I think they  default to an isolated VM network (but maybe I'm thinking it's like docker in this way that it's not).

**Haven't been able to try this for the next failure (can't connect to console)** ~~'boot failed not a bootable disk' error.  Testing editing the VM (via `virsh edit archrouter`) to point to 'index="3"' since / was mounted on the the /dev/sda3 partition.~~

Couldn't connect to console => ??? ([this](https://ravada.readthedocs.io/en/latest/docs/config_console.html) apparently requires me to start a service in the VM.  I'm not sure how I'm supposed to do that when I can't connect to it (i.e., sounds like a chicken-and-egg problem).)