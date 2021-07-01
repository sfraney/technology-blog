---
title: "Creating KVM Guest with GPU Passthrough"
date: 2021-07-01
description: ""
summary: ""
draft: false
tags: []
---

## TODO

## Introduction

## Process

Consolidated information from a few blogs and the Arch Wiki:
- [^ref1][Heiko Sieger](https://www.heiko-sieger.info/creating-a-windows-10-vm-on-the-amd-ryzen-9-3900x-using-qemu-4-0-and-vga-passthrough/ "Windows 10 VM on Ryzen 9 3900x")
- [^ref2][Bryan Steiner](https://github.com/bryansteiner/gpu-passthrough-tutorial "GPU passthrough tutorial")
- [^ref3][Mathias Hueber](https://mathiashueber.com/pci-passthrough-ubuntu-2004-virtual-machine/ "Virtual machines with PCI passthrough on Ubuntu 20.04")
- [^ref4] Arch Linux Wiki: [PCI passthrough via OVMF](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF "PCI passthrough via OVMF")
- [^ref5] Ubuntu Wiki: [KVM Installation](https://help.ubuntu.com/community/KVM/Installation "KVM Installation")

1. Install packages.  The various blogs suggest slightly different package combinations:
   - `qemu-kvm qemu-utils libvirt-daemon-system libvirt-clients virt-manager ovmf`
   - `libvirt-daemon-system libvirt-clients qemu-kvm qemu-utils virt-manager ovmf`
   - `qemu-kvm qemu-utils libvirt-daemon-system libvirt-clients bridge-utils virt-manager ovmf`
   - When re-organized, it boils down to all suggesting `qemu-kvm qemu-utils libvirt-daemon-system libvirt-clients virt-manager ovmf` with one additionally suggesting `bridge-utils` => I will take the subset and only add `bridge-utils` if I end up finding a use for it down the road.
   - Add user to `libvirt` and `kvm` groups[^ref5]: `sudo adduser `id -un` libvirt` and `sudo adduser `id -un` kvm`
1. Enable IOMMU
    1. Edit `/etc/default/grub` to contain the following (along with any existing directives): `GRUB_CMDLINE_LINUX_DEFAULT="amd_iommu=on iommu=pt"`
        - Note, not all suggest the `iommu=pt`[^ref1] **(and I'm not sure whether it should be `iommu=pt` or `amd_iommu=pt`)**, but [this blog](https://www.heiko-sieger.info/creating-a-windows-10-vm-on-the-amd-ryzen-9-3900x-using-qemu-4-0-and-vga-passthrough/ "Windows 10 VM on Ryzen 9 3900x") indicates it "tells the kernel to bypass DMA translation to the memory, which may improve performance."
        - Maybe add `hugepages=8192` also[^ref1]?
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
1. Extend the `GRUB_CMDLINE_LINUX_DEFAULT` further to pass the GPU through to the VFIO driver: `vfio_pci.ids=<vendor id>:<model id> kvm.ignore_msrs=1` (e.g., `vfio_pci.ids=10de:13c2,10de:0fbb kvm.ignore_msrs=1`)
    - Be sure to grab all the devices associated with the GPU (e.g., video and audio)
    - Note, I can use the device IDs (as preferred) since my graphics cards are different.  If they were the same, some other approach would be necessary
    - Take note also of some good USB controller devices for later (and probably the hard drive that will be passed through).  At this point, it's _probably_ fine to just play around with the GPU?
    - May not need `kvm.ignore_msrs=1`[^ref3]
1. Grab VFIO drivers [https://docs.fedoraproject.org/en-US/quick-docs/creating-windows-virtual-machines-using-virtio-drivers/index.html](https://docs.fedoraproject.org/en-US/quick-docs/creating-windows-virtual-machines-using-virtio-drivers/index.html)
    - Seems to be just for Windows Guests (maybe why I couldn't get one working before...)
