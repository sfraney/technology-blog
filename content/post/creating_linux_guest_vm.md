---
title: "Creating Linux KVM Guest with GPU Passthrough"
date: 2021-07-01
description: ""
summary: ""
draft: false
tags: []
---

triggering uevents

## Tricky Issues

- Had HDMI plugged into graphics card at startup and saw it get assigned vfio-pci driver (good), but _mostly_ black screen (one big cursor) when VM started up.  If I was patient (probably 5 - 10 minutes), sometimes I would be able to enter my username and it would ask for a password (in big characters).  Thinking I was getting somewhere (even though Live USB shouldn't ask for that stuff), I Ctrl-C'd since I don't wanna put my password into something I don't recognize, and it refreshed to show _my hypervisor's terminal_ (WTF).

Eventually, I happened to go looking for log to figure out my libvirt version to see if disk `type='nvme'` was supported (I was barking up the NVMe tree, thinking it might be a problem that I didn't pass a disk - `--disk none`) and found logs of my VM which showed a bunch of `qemu-system-x86_64: vfio_region_write failed: Device or resource busy` messages.  A quick search online (filtering out "unraid" results via `-unraid` in the search) led me a [mailing list archive](https://listman.redhat.com/archives/vfio-users/2016-March/msg00085.html "[vfio-users] - Device or Resource Busy") that led to my issue.  Like the poster, I had `efifb` glomming onto my graphics card.  Assuming it was because it was plugged in to beging boot, I rebooted with it unplugged and all was well.
- Adding `video=efifb:off` to `GRUB_CMDLINE_LINUX_DEFAULT` and running `update-grub`, as suggested in the last response in the thread, seems to fix the issue, allowing me to keep the monitor plugged in

- Couldn't install Arch Linux as guest, but Linux Mint worked fine.  I didn't want to settle for Mint when I wanted to switch to Arch and it turned out the problem was a typical one:
    - After `triggering uevents` the screen seemed to smear with just the bottom tenth or so showing illegible text.  I could tell it was responding to my keystrokes by seeing changes in the smear and the fact that `shutdown -h now` shut the VM down
    - Needed to disable KMS (Kernel Mode Setting) via `nomodeset` per the [Arch Wiki](https://wiki.archlinux.org/title/Kernel_mode_setting#Disabling_modesetting "Disabling Kernel Mode Setting"), I pressed 'e' at the boot menu and added `nomodeset nouveau.modeset=0` to the line

- EFI boot order had EFI shell ahead of the disc and updates (including `efibootmgr` and selection of Boot Manager -> Boot Options -> Change Boot Order with "Commit" changes) didn't stick.  Per [this post](https://forums.unraid.net/topic/91074-ovmf-boot-order-wont-commit-solved/?do=findComment&comment=844968)(despite the fact that UnRaid questions and answers are both very high in search results _and_ very low in success rate), I was able to get it fixed by removing `boot` arguments from the `os` section and marking the discs as `<boot order='1'/>`

## TODO

### Issues
- ~~~USB hot plug of Keyboard and Mouse don't seem to work~~~
    - Had to do next step to get it to work
- ~~~Need to pass Keyboard and Mouse through their controller rather than vendor/product because that requires them to be connected (e.g., not being used by laptop via KVM switch)~~~
    - Passed through USB controller by PCI address and trial-and-error to see what ports it was associated with
- Always booting into EFI where I have to manually select the boot drive (`exit` at EFI shell -> Boot Manager or something like that -> select boot drive)
    - tried several solutions, none stuck
        - `efibootmgr -o ...` in guest
        - Boot Manager -> Boot Options -> Change Boot Order (with Commit Changes) in EFI shell

I think these can be done after initial setup of the guest (i.e., can/must modify the resulting XML afterward)
- Figure out networking
    -- Note, this is important because default networking will put the PCs behind the KVM router which will make it harder to access them from other machines on the LAN
- ~~~Fake out the NVIDIA GPU to make it think it's _not_ in a guest (NVIDIA wants you to buy more expensive Quadro parts if you want to do virtualization)~~~

## Introduction

## Process

Consolidated information from a few blogs and the Arch Wiki:
- [^ref1] [Heiko Sieger](https://www.heiko-sieger.info/creating-a-windows-10-vm-on-the-amd-ryzen-9-3900x-using-qemu-4-0-and-vga-passthrough/ "Windows 10 VM on Ryzen 9 3900x")
- [^ref2] [Bryan Steiner](https://github.com/bryansteiner/gpu-passthrough-tutorial "GPU passthrough tutorial")
- [^ref3] [Mathias Hueber](https://mathiashueber.com/pci-passthrough-ubuntu-2004-virtual-machine/ "Virtual machines with PCI passthrough on Ubuntu 20.04")
- [^ref4] Arch Linux Wiki: [PCI passthrough via OVMF](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF "PCI passthrough via OVMF")
- ~~~[^ref5] Ubuntu Wiki: [KVM Installation](https://help.ubuntu.com/community/KVM/Installation "KVM Installation")~~~
- [^ref6] A [blog](https://frdmtoplay.com/virtualizing-windows-7-or-linux-on-a-nvme-drive-with-vfio/#builddriveriso) I didn't use, but that may be useful for setting up a Windows guest

### Setup the system
1. Install packages.  The various blogs suggest slightly different package combinations:
   - `qemu-kvm qemu-utils libvirt-daemon-system libvirt-clients virt-manager ovmf`
   - `libvirt-daemon-system libvirt-clients qemu-kvm qemu-utils virt-manager ovmf`
   - `qemu-kvm qemu-utils libvirt-daemon-system libvirt-clients bridge-utils virt-manager ovmf`
   - When re-organized, it boils down to all suggesting `qemu-kvm qemu-utils libvirt-daemon-system libvirt-clients ~~virt-manager~~ ovmf` with one additionally suggesting `bridge-utils` => I will take the subset and only add `bridge-utils` if I end up finding a use for it down the road.
    -- Note, striking through `virt-manager` since I'm on Ubuntu Server and `virt-manager` is the GUI.  May end up adding `virt-install`, though
   - Add user to `libvirt` and `kvm` groups[^ref5]: `sudo adduser `id -un` libvirt` and `sudo adduser `id -un` kvm`
    -- This didn't appear to be necessary: `virsh list --all` worked as my normal user after the install
1. Enable IOMMU
    1. Edit `/etc/default/grub` to contain the following (along with any existing directives): `GRUB_CMDLINE_LINUX_DEFAULT="amd_iommu=on iommu=pt"`
        - Note, not all suggest the `iommu=pt`[^ref1] **(and I'm not sure whether it should be `iommu=pt` or `amd_iommu=pt`)**, but [this blog](https://www.heiko-sieger.info/creating-a-windows-10-vm-on-the-amd-ryzen-9-3900x-using-qemu-4-0-and-vga-passthrough/ "Windows 10 VM on Ryzen 9 3900x") indicates it "tells the kernel to bypass DMA translation to the memory, which may improve performance."
        - Maybe add `hugepages=8192` also[^ref1]?
        - Note, I ended up using `amd_iommu=pt` in the end
    1. Tell GRUB to pick up the changes: `update-grub`
1. Reboot
1. Identify the IOMMU groups
    - Either this[^ref2]
    ```#!/bin/bash
    for d in /sys/kernel/iommu_groups/*/devices/*; do
        n=${d#*/iommu_groups/*}; n=${n%%/*}
        printf 'IOMMU Group %s ' "$n"
        lspci -nns "${d##*/}"
    done```
    - OR[^ref3] -
    ```#!/bin/bash
    # change the 999 if needed
    shopt -s nullglob
    for d in /sys/kernel/iommu_groups/{0..999}/devices/*; do
        n=${d#*/iommu_groups/*}; n=${n%%/*}
        printf 'IOMMU Group %s ' "$n"
        lspci -nns "${d##*/}"
    done;```
    - OR, most simply[^ref1] -
    `for a in /sys/kernel/iommu_groups/*; do find $a -type l; done | sort --version-sort`
        -- This one fails to include details of _what_ each device is
1. Extend the `GRUB_CMDLINE_LINUX_DEFAULT` further to pass the GPU through to the VFIO driver: `vfio_pci.ids=<vendor id>:<model id> kvm.ignore_msrs=1` (e.g., `vfio_pci.ids=10de:2484,10de:228b kvm.ignore_msrs=1`)
    - Be sure to grab all the devices associated with the GPU (e.g., video and audio)
    - Note, I can use the device IDs (as preferred) since my graphics cards are different.  If they were the same, some other approach would be necessary
    - Take note also of some good USB controller devices for later (and probably the hard drive that will be passed through).  At this point, it's _probably_ fine to just play around with the GPU?
    - May not need `kvm.ignore_msrs=1`[^ref3]
1. Grab VFIO drivers [https://docs.fedoraproject.org/en-US/quick-docs/creating-windows-virtual-machines-using-virtio-drivers/index.html](https://docs.fedoraproject.org/en-US/quick-docs/creating-windows-virtual-machines-using-virtio-drivers/index.html)
    - Seems to be just for Windows Guests (maybe why I couldn't get one working before...)
    - One blog[^ref2] referenced another[^ref6] as a resource here

### Create the guest

- See ["Additional XML Configurations"](https://www.heiko-sieger.info/creating-a-windows-10-vm-on-the-amd-ryzen-9-3900x-using-qemu-4-0-and-vga-passthrough/)
In "features" block:
- `<vendor_id state="on" value="0123456789ab"/>`
- AND-
    ```<kvm>
        <hidden state="on"/>
    </kvm>```
- Network - setup a bridge?
- CPU
    - vcpus vs. _real_ cpus?
        - vcpus are number of threads
    - `--vcpus 16 maxvcpus=32`
- Memory
 - would like to have minimum reservation, but up to max (e.g., 16GB -> 32GB)
 - `--memory 16384 maxMemory=32768`
- Disk
    - Passthrough - via `host-dev`?
    - How to specify none (like GPU)?  Just omit `--disk`?
- GPU - `--graphics none`

## Results

After overcoming a couple obstacles, I finally was presented with a GRUB command line at the Arch Linux boot.  After trying a few things, I threw up my hands and just installed a Manjaro guest.  Based on Arch Linux, it will hopefully scratch my itch (e.g., always have cutting edge packages) and I can actually use it.
