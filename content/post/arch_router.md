---
title: "Building a Home Router"
date: 2021-05-30
description: ""
summary: ""
draft: false
time: ""
tags: []
---

## Hardware

## Software

Arch Linux - rationale: theoretically, rolling updates limit vulnerability window.  In reality, I'm not that great at keeping updated and being on the cutting edge opens you up to non-malicious breakage.  We'll see how it works out.

### OS Installation
[Arch Linux Installation Guide](https://wiki.archlinux.org/title/Installation_guide "Arch Linux Installation Guide")

- mkfs.fat -F 32 /dev/efi-partition (from [Arch Linux Wiki](https://wiki.archlinux.org/title/FAT "Arch Linux Wiki for FAT")
- Don't ignore the seemingly minor suggestin that you install a bootloader.  I did't actually miss this, but thought it was weird to not have prominently displayed.  Maybe there's something about the base install that will make everything work, but generally, not having a bootloader seems like very bad things would happen (as in, you wouldn't boot).

#### Further configuration

- Setup networking [https://the-empire.systems/arch-linux-router](https://the-empire.systems/arch-linux-router "build a router in Arch Linux")
  1. Create persistent interface names via ['link'](https://wiki.archlinux.org/title/Systemd-networkd#Renaming_an_interface "renaming and interface")
  1. Point to nameserver on existing router (from [https://gist.github.com/eltonvs/d8977de93466552a3448d9822e265e38](https://gist.github.com/eltonvs/d8977de93466552a3448d9822e265e38 "gist"): open `/etc/resolv.conf` and add the following:
  ```nameserver <IP of existing router>```
- Create admin account - combination of [https://www.vultr.com/docs/create-a-sudo-user-on-arch-linux](https://www.vultr.com/docs/create-a-sudo-user-on-arch-linux "create a sudo user on Arch Linux") and [https://wiki.archlinux.org/title/Users_and_groups#User_management](https://wiki.archlinux.org/title/Users_and_groups#User_management "User and Group Management - Arch Linux wiki")
  1. Create user with home directory and part of the `wheel` group: `useradd -m -G wheel admin`
  1. Give new user a password: `passwd admin`
  1. Install sudo: `pacman -S sudo`
  1. Allow `wheel` group members to elevate privileges: `visudo` (ensures sanity of the resulting file) and uncomment `%wheel ALL=(ALL) ALL`
- OpenSSH
  1. Install OpenSSH: `pacman -S openssh`
  1. Enable sshd: `systemctl enable sshd`
  1. Start sshd: `systemctl start sshd`
  1. Test and enable login without password (from [http://www.linuxproblem.org/art_9.html)](http://www.linuxproblem.org/art_9.html "SSH login without password")
  1. Disable password-based authentication: set `PasswordAuthentication no` in `/etc/ssh/sshd_config`
- **After verifying `admin` viability (e.g., by setting up ssh with it),** disable root login: `passwd --lock root`

### Router services
The following sections relied heavily on the following sources along with a variety of other, more specific references (which I'll try to call out in their sections):

- [https://arstechnica.com/gadgets/2016/04/the-ars-guide-to-building-a-linux-router-from-scratch/](https://arstechnica.com/gadgets/2016/04/the-ars-guide-to-building-a-linux-router-from-scratch/ "Ars Guide to Building a Router")
- [https://blog.bigdinosaur.org/running-bind9-and-isc-dhcp/](https://blog.bigdinosaur.org/running-bind9-and-isc-dhcp/ "More Sophisticated DNS and DHCP Configuration")
- [https://the-empire.systems/arch-linux-router/](https://the-empire.systems/arch-linux-router/ "Basic Router in Arch Linux")

**In the appropriate section below, be sure to call out that Arch (or maybe systemd) has a different way to enable forwarding than other systems and the one at [https://the-empire.systems/arch-linux-router/](https://the-empire.systems/arch-linux-router/ "Basic Router in Arch Linux") is _mostly_ it:[^sysctl]** `echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.d/10-ip_forward.conf && sudo sysctl -p /etc/sysctl.d/10-ip_forward.conf`

#### DHCP

#### DNS

#### IPTables

### Enabling second LAN interface

[https://wiki.archlinux.org/title/Network_bridge](https://wiki.archlinux.org/title/Network_bridge "Arch wiki network bridge")

- Make sure interface for LAN have consistent name by creating .link files for them, for easy binding in the binding below (not to mention easy identification based on names)
  1. Make sure .link files name the LAN interfaces `enlan*`
- Create bridge
  1. Create netdev (virtual network device) for the bridge (lexically after the links, but before the networks)
  ```/etc/systemd/network/15-bridge.netdev
  [NetDev]
  Name=br0
  Kind=bridge```
     --- Set MACAddress? `MACAddress=xx:xx:xx:xx:xx:xx`
  1. Restart systemd-networkd to create bridge
  1. Bind bridge to network interface(s)
  ```/etc/systemd/network/16-bound.network
  [Match]
  Name=enlan*

  [Network]
  Bridge=br0```
  **Make sure any interface does _not_ have DHCP or static IP address assigned** (i.e., "modify the corresponding `/etc/systemd/network/<iface>.network` accordingly to remove the addressing")**
  Most easy to do by just repurposing the existing 21-lan.network for the next step
  1. Configure IP & DNS for the bridge (probably will match one of the interfaces that had it's addressing removed in the previous step)
  ```/etc/systemd/network/21-lan.network
  [Match]
  Name=br0

  [Network]
  Address=172.16.0.1/24```
  (Note, I removed the `DNS` and `Gateway` portions from the wiki.  Hopefully they're not needed because they seem to be problematic since the bridge is the one that will handle both...)

- Update iptables rules to forward traffic between WAN and new bridge rather than any existing single interface

### Moving To Serve the House

- Remove all references to 192.*
  -- **What to do about /etc/resolv.conf?**  Change to internet DNS (e.g., 8.8.8.8)?

## Personal concerns

Tricky parts due to my specific situation

### NFS shared /home

Need to update /etc/fstab of affected machines (hypervisor & VM) to point to new IP addresses before switching over networks.

#### Background
My "main" PC is a Linux Mint 20 KVM virtual machine with GPIO passthrough of the GPU.  I run the hypervisor alongside my old baremetal OS (Linux Mint 19) that was installed with a separate /home partition in the hopes that I could perform clean OS upgrades without affecting my day-to-day data.  That was a bad assumption (see above with my comment on not updating too frequently) that led to issues like the root partition ending up too small.

In any case, I have this /home partition sitting around and I thought I'd give the "upgrade without affecting day-to-day data" by using the same /home for both the baremetal and VM OSs.  I accomplish this by mounting /home (under /mnt) in my hypervisor and sharing it via NFS.  This means my /etc/fstab has the IP address for my hypervisor (oh, I use bridged(?) networking for my VM, too)[^dns].  This is obviously a problem when the IP addresses change and my VM OS can't log me in for lack of a /home directory[^actually].

[^sysctl]: Per [this thread](https://bbs.archlinux.org/viewtopic.php?id=170005 "Wrong Defaults for sysctl -p"), need to specify conf file explicitly or could probably direct command to /etc/sysctl.conf instead of the one under /etc/sysctl.d

[^dns]: Ideally, I think, DNS should have helped me here, by allowing me to refer to the hypervisor by name rather than IP, but my (old) router doesn't have it, which is one thing I'm looking forward to having with this homemade router.

[^actually]: Actually, I can log in via a text terminal (e.g., TTY1) to fix this up if I forget to fix this beforehand.
