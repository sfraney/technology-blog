---
title: "Arch Hypervisor Plan"
date: 2025-12-06
description: "Upgrading my system to a rolling release"
summary: ""
draft: false
tags: ["arch linux", "zfs", "server", "kvm"]
---

It has been 4 1/2 years since I first setup my 2-desktops-in-1 hybrid hypervisor/home-server system. I used the most recent Ubuntu LTS at the time - 20.04 - and it is now no longer supported. This has taught me that I need something that can last longer than LTS provides and I have become more comfortable with Arch Linux in the last 4+ years, so I'm going to update to an Arch Linux system.

The challenge is that this system hosts a lot and I don't want anything to slip through the cracks. My strategy is to use the existing 1TB 'temp' ZFS pool drive (which only has 37GB used) for a side-by-side Arch installation, allowing me to develop the new system while the old one is still available in a dual boot configuration.

## System Overview

### Hardware
- **CPU**: Ryzen 9 5950x
- **GPUs**: 1x NVIDIA 3070, 1x AMD XFX Radeon HD 6950 (for VM passthrough - mixed vendors to avoid GRUB blacklisting issues)
- **NVMe drives**: 2x (both for VM passthrough - motherboard only supports 2)
- **OS drive**: 372.6 GB Hitachi HDT72504
- **ZFS pools**: 
  - `tank`: 3x8TB RAIDZ
  - `temp`: 1TB (only 37GB used - candidate for Arch installation)
- **SSDs**: 3x250GB (need to determine current use - possibly [L2ARC/SLOG]({{< ref "zfs" >}}) for tank pool, or download zpool)

### Current Services
- **Docker containers (ports)**: Jellyfin (8096), Sonarr (8989), Radarr (7878), HomeAssistant (8123), Deluge (58846), Nextcloud (w/ MariaDB), Unifi Controller
  - Helper containers
    - For HomeAssistant: Frigate, MQTT
    - Prometheus, Grafana, node-exporter, cadvisor
- **Virtualization**: 2x KVM VMs with GPU passthrough ([Windows]({{< ref "creating_windows_guest_vm" >}}) + [Linux]({{< ref "creating_linux_guest_vm" >}}))
- **Storage**: ZFS auto-snapshots, [AWS Glacier backups]({{< ref "offsite_backup" >}})
- **Network**: Bridge networking, hostname: hypervisor.local
- **Router Backup**: Weekly backup of Arch router on Mondays at 01:00

### Key Considerations
- No [CPU pinning or huge pages]({{< ref "perf_tuning_vms" >}}) currently configured
- No regular full system backup (needs to be implemented)
- IOMMU/VFIO configuration must be preserved (mixed GPU vendors avoid GRUB blacklisting issues)
- All services must continue functioning

## Phase 1: System Census

Before making any changes, I need a complete inventory of the current system. This will help ensure nothing is missed during migration. All census output will be saved to `static/census/arch-hypervisor-migration/` in the blog repository for reference, with files named by date and category.

### Storage Inventory

Output will be saved to `static/census/arch-hypervisor-migration/<date>-storage-inventory.txt`.

```bash
# List all block devices
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,UUID

# ZFS pool status (all pools)
zpool status
zpool status -v

# Detailed ZFS pool information including cache/SLOG
zpool status tank
zpool list -v

# Filesystem usage
df -h
df -hT

# Mount points
mount | sort
cat /etc/fstab

# Disk partitions
sudo fdisk -l
lsblk -f
```

**Key questions to answer:**
- Which drive is the OS drive? (372.6GB or one of the 3x250GB?)
- What are the 3x250GB SSDs currently doing?
  - Are they L2ARC/SLOG for 'tank' pool?
  - Are they part of a download zpool?
  - Are they unused?
- What's in the 37GB on 'temp' pool?
- What's the exact layout of the 1TB temp pool drive?

**Answers from census:**

- **OS drive**: `sdb` (372.6GB Hitachi HDT72504) - Contains `/boot/efi` (512M), `/boot` (1G ext4), and root filesystem (185.6G ext4 on LVM volume `ubuntu--vg-ubuntu--lv`)

- **3x250GB SSDs** (`sda`, `sdc`, `sdd` - Samsung SSD 850/840, 238.5GB each):
  - Each drive has 3 partitions:
    - `part1`: 16G (Linux filesystem, not clearly identified)
    - `part2`: 2G zfs_member labeled "tank" (not currently used as [L2ARC/SLOG]({{< ref "zfs" >}}) - tank pool only shows the 3x8TB drives)
    - `part3`: 220.5G zfs_member labeled "downloads"
  - The `part3` partitions form a striped "downloads" zpool (660G total, 621G used, 94% capacity)
  - **Not** used as L2ARC/SLOG for 'tank' pool
  - **Are** part of the "downloads" zpool (striped across all three SSDs)

- **Temp pool contents**: 36.5GB used out of 904GB total (4% capacity). Pool is in DEGRADED state with 1 data error from a scrub in December 2023. The drive (`sdh3`) shows "too many errors" in the zpool status.

- **1TB temp pool drive layout** (`sdh` - WDC WD10EZEX-00K, 931.5GB):
  - `sdh1`: 22.4GB ext4 (not mounted, old OS partition - **Ubuntu 12.04.3 LTS (Precise Pangolin)**)
  - `sdh2`: 1KB (extended partition)
  - `sdh3`: 905.2GB zfs_member (temp pool - DEGRADED, lightly used)
  - `sdh5`: 4GB swap partition
  
  **Conclusion**: The 1TB drive (`sdh`) was previously used as an OS disk (Ubuntu 12.04.3 LTS from 2012 on `sdh1`) and now contains a lightly-used, degraded ZFS dataset on `sdh3`. Once the temp pool data is backed up, this drive can be fully repurposed for the new Arch Linux installation.

### Network Configuration

Output will be saved to `static/census/arch-hypervisor-migration/<date>-network-config.txt`.

```bash
# Network interfaces
ip addr show
# or
ifconfig -a

# Network configuration files
ls -la /etc/netplan/
cat /etc/netplan/*.yaml
# or
cat /etc/network/interfaces

# Bridge configuration
brctl show
ip link show type bridge

# Firewall rules
sudo ufw status verbose
# or
sudo iptables -L -v -n
sudo iptables -t nat -L -v -n

# Routing
ip route show
```

**Key findings from census:**

- **Physical interface**: `enp6s0` (bridged, not directly configured)
- **Bridge**: `br0` bridges `enp6s0`, receives IP via DHCP (currently `172.16.0.202/24`)
- **VM networking**: VMs use `br0` via `vnet0` and `vnet1` (not the default `virbr0` which is unused)
  - This allows VMs to be on the same LAN as the host (not behind NAT), making them accessible from other machines on the network
- **Configuration**: Netplan (`/etc/netplan/00-installer-config.yaml`) - manually modified to configure bridge
- **Firewall**: UFW inactive (no firewall rules)
- **Docker networks**: Many auto-created Docker bridge networks (not critical to document individually)

**Note**: This configuration will need to be replicated on Arch Linux. The bridge setup is critical for VM networking to function correctly. Both the host and VMs use `br0`, allowing VMs to appear as regular devices on the LAN rather than being NAT'd behind the hypervisor.

### Services Inventory

Output will be saved to `static/census/arch-hypervisor-migration/<date>-services-inventory.txt`.

```bash
# Systemd services
systemctl list-units --type=service --state=running
systemctl list-units --type=service --state=enabled
systemctl list-units --type=timer --state=running

# Docker containers
docker ps -a
docker images
docker volume ls

# Docker directory structure
ls -laR $HOME/docker/

# Cron jobs
crontab -l
sudo crontab -l
ls -la /etc/cron.*
cat /etc/crontab
```

**Key findings from census:**

- **Docker containers (15 running)** - More services than originally documented (~~struckthrough~~ are not desired on the new system):
  - **Media**: Jellyfin (8096), Sonarr (8989), Radarr (7878), Deluge (8112, 58846), ~~CouchPotato (5050)~~
  - **Home automation**: HomeAssistant (8123), Frigate (8554-8555, 8971), MQTT broker (1883)
  - **Cloud**: Nextcloud (443) with MariaDB
  - **Monitoring**: Prometheus (9090), Grafana (3000), node-exporter (9100), cadvisor (8080)
  - **Network**: Unifi Controller (multiple ports)
  - **Note**: ZoneMinder referenced in cron jobs but not currently running

- **Systemd services**: 32 running services including:
  - `libvirtd` and `virtlogd` for virtualization
  - `zfs-zed` for ZFS event handling
  - `docker` and `containerd` for container runtime
  - No systemd timers running (all automation via cron)

- **Cron-based automation** (critical to migrate, except those ~~struckthrough~~):
  - **ZFS auto-snapshots**: Every 15 minutes (`/home/$USER/scripts/perl-zfs-auto-snap/zfs-auto-snap.pl`)
  - **AWS Glacier backups**: Weekly on Mondays at 18:00 (`/home/$USER/scripts/aws_backup/aws_backup.pl`)
  - **ZFS scrub**: Weekly on Mondays at 00:00 (`zpool scrub tank`)
  - **Router backup**: Weekly on Mondays at 01:00 (`/home/$USER/scripts/archrouter_full_backup.sh`)
  - ~~**System shutdown**: Every 15 minutes Tue-Sat (`/home/$USER/scripts/shutdown_system_w_no_guests.sh`)~~
  - ~~**Camera management**: ZoneMinder/HomeAssistant stop at 19:30, start at 7:30-7:31~~
  - ~~**HomeAssistant startup**: On boot (`/home/$USER/scripts/start_home_assistant.sh`)~~

- **Scripts to migrate** (located in `/home/$USER/scripts/`, ~~struckthrough~~ unnecessary):
  - `archrouter_full_backup.sh`
  - `perl-zfs-auto-snap/zfs-auto-snap.pl`
  - `aws_backup/aws_backup.pl`
  - ~~`start_home_assistant.sh`~~
  - ~~`shutdown_system_w_no_guests.sh`~~

- **Docker configuration**: All containers configured via docker-compose files in `/home/$USER/docker/` subdirectories

### VM Configuration

VM XML exports will be saved to `/tank/backup/vm-<vm-name>.xml`. Other VM configuration output will be saved to `static/census/arch-hypervisor-migration/<date>-vm-config.txt`.

```bash
# List all VMs
virsh list --all

# Export VM XML configurations
virsh dumpxml <vm-name> > /tank/backup/vm-<vm-name>.xml

# IOMMU groups
for d in /sys/kernel/iommu_groups/*/devices/*; do
    n=${d#*/iommu_groups/*}; n=${n%%/*}
    printf 'IOMMU Group %s ' "$n"
    lspci -nns "${d##*/}"
done

# PCI devices
lspci -nn

# GPU information (critical for VFIO configuration)
lspci -nn | grep -i vga
lspci -nn | grep -i "3d\|display"
# Get full GPU details including audio devices
lspci -nn | grep -E "(NVIDIA|AMD|Radeon)"
```

**Key findings from census:**

- **VMs**: 2 running (User1-PC, User2-PC), 5 shut off (CppDev, Manjaro.24.1.2, qcow-reader, Spare-PC-1, Spare-PC-2)

- **GPU PCI IDs for VFIO configuration** (critical for Arch setup):
  - **AMD Radeon HD 6950**: `1002:6719` (VGA) + `1002:aa80` (Audio) - IOMMU Group 23
  - **NVIDIA 3070**: `10de:2484` (VGA) + `10de:228b` (Audio) - IOMMU Group 25
  - Both GPUs are in isolated IOMMU groups with their audio devices (ideal for passthrough)

- **NVMe drives for passthrough**:
  - `01:00.0` - Sandisk NVMe (IOMMU Group 14) - passed to User1-PC
  - `04:00.0` - Sandisk NVMe (IOMMU Group 22) - passed to User2-PC

- **VM configuration differences**:
  - **User1-PC**: 12GB RAM, 8 vCPUs, UTC clock, NVIDIA GPU, no KVM hidden state
  - **User2-PC**: 16GB RAM, 8 vCPUs, localtime clock, AMD GPU, KVM hidden state enabled, CPU topology specified, `smep` disabled

- **PCI devices passed through**:
  - **User1-PC**: NVIDIA GPU + audio (0a:00.0, 0a:00.1), USB controller (0c:00.3), NVMe drive (01:00.0)
  - **User2-PC**: AMD GPU + audio (05:00.0, 05:00.1), NVMe drive (04:00.0), USB controllers (07:00.1, 07:00.3), AMD HD Audio (0c:00.4)

- **IOMMU groups**: Well-isolated - each GPU is in its own group with its audio device, which is ideal for passthrough

- **Network**: Both VMs confirmed to use `br0` bridge (verified from VM XML exports)

### System Configuration

Package list will be saved to `/tank/backup/ubuntu-packages.txt`. Other system configuration output will be saved to `static/census/arch-hypervisor-migration/<date>-system-config.txt`.

```bash
# Boot configuration
cat /etc/default/grub
cat /boot/grub/grub.cfg

# Installed packages
dpkg --get-selections | grep -v deinstall > /tank/backup/ubuntu-packages.txt

# User accounts
cat /etc/passwd
cat /etc/group
id

# SSH configuration
cat ~/.ssh/config
cat ~/.ssh/authorized_keys
ls -la ~/.ssh/
```

**Key findings from census:**

- **GRUB VFIO configuration** (critical for Arch migration):
  - Kernel parameters: `video=efifb:off amd_iommu=on iommu=pt vfio_pci.ids=10de:2484,10de:228b,10de:11c0,10de:0e0b,1002:6719,1002:aa80`
  - NVIDIA GPU: `10de:2484` (VGA) + `10de:228b` (Audio) + additional devices `10de:11c0`, `10de:0e0b`
  - AMD GPU: `1002:6719` (VGA) + `1002:aa80` (Audio)
  - Boot settings: `GRUB_TIMEOUT=0` with `GRUB_TIMEOUT_STYLE=hidden` (immediate boot to default)

- **Installed packages**: 980 packages total
  - **Critical for migration**: Docker (`docker-ce`, `docker-compose-plugin`), virtualization (`qemu-kvm`, `libvirt-daemon`, `ovmf`), ZFS (`zfsutils-linux`), AWS CLI (`awscli`), network (`netplan.io`)
  - No desktop environment packages (server/hypervisor setup confirmed)

- **User accounts**: 
  - `user1` (UID 1000) - primary user with sudo, libvirt, docker groups
  - `user2` (UID 1001) - secondary user with libvirt, www-data, sambashare groups
  - `deluge` (UID 1002) - service account for Deluge container

- **SSH configuration**:
  - Three authorized keys from multiple machines (Raspberry Pi and local user PCs)
  - No SSH config file (using defaults)

- **GRUB menu entries**:
  - Current Ubuntu 20.04 entries (5.4.0-216-generic and 5.4.0-212-generic)
  - Windows Boot Manager entry (dual-boot configuration)
  - **Old Ubuntu 12.04.3 LTS entries** on `/dev/sdh1` (should be cleaned up after migration - matches old OS partition found in storage inventory)

- **Note**: The `grub.cfg` file is very long (804+ lines) due to multiple kernel versions and old OS entries. The full file was captured in the census output for reference, but only the `/etc/default/grub` configuration is needed for Arch migration.

### Backup and Automation Scripts

Output will be saved to `static/census/arch-hypervisor-migration/<date>-backup-scripts.txt`.

```bash
# Find backup scripts
find /home -name "*backup*" -type f
find /usr/local/bin -name "*backup*" -type f
find /etc -name "*backup*" -type f

# ZFS snapshot automation
systemctl list-timers | grep -i snap
grep -r "zfs.*snap" /etc/cron.*
grep -r "zfs.*snap" /home/*/bin

# AWS backup scripts
grep -r "aws.*s3" /home
grep -r "glacier" /home

# Document known scripts (from Services Inventory)
ls -laR /home/$USER/scripts/
cat /home/$USER/scripts/archrouter_full_backup.sh
cat /home/$USER/scripts/perl-zfs-auto-snap/zfs-auto-snap.pl | head -50
cat /home/$USER/scripts/aws_backup/aws_backup.pl | head -50

# Check script dependencies
head -20 /home/$USER/scripts/perl-zfs-auto-snap/zfs-auto-snap.pl | grep -E "^use|^require"
head -20 /home/$USER/scripts/aws_backup/aws_backup.pl | grep -E "^use|^require|import"
```

**Key findings from census:**

- **Scripts to migrate** (located in `/home/$USER/scripts/`):
  - `archrouter_full_backup.sh` - Weekly router backup script (runs Mondays at 01:00 via cron)
  - `perl-zfs-auto-snap/zfs-auto-snap.pl` - ZFS auto-snapshot script (runs every 15 minutes via cron)
  - `aws_backup/aws_backup.pl` - AWS Glacier backup script (runs weekly Mondays at 18:00 via cron)

- **Scripts NOT needed** (do not migrate):
  - `start_home_assistant.sh` - HomeAssistant startup script (no longer needed)
  - `shutdown_system_w_no_guests.sh` - System shutdown script (no longer needed)

- **Automation method**: All scripts run via cron jobs (no systemd timers). See [Services Inventory](#services-inventory) section for full cron job details.

- **Git repositories**: Both `aws_backup/` and `perl-zfs-auto-snap/` directories are git repositories - can be cloned/pulled rather than just copied during migration

- **Perl dependencies** (specific modules required):
  - `zfs-auto-snap.pl`: Requires `POSIX` and `DateTime` Perl modules
  - `aws_backup.pl`: Dependencies not visible in first 20 lines (longer script), needs full review

- **AWS backup configuration**:
  - AWS S3 bucket: `<redacted>`
  - Configuration files to migrate:
    - `/home/$USER/backup/dataset_backup_passphrases` - Encryption passphrases for datasets
    - `/home/$USER/backup/latest_backup_snaps` - Log file tracking backed up snapshots
  - AWS CLI credentials and config files also need migration

- **Router backup method**: Uses hard links (`cp -al`) for efficient storage of timestamped backups in `/tank/backup/archrouter.backup/`

- **ZFS snapshot configuration**: `zfs-auto-snap.pl` manages snapshots for 9 datasets with retention policies (frequent: 4, hourly: 24, daily: 31, weekly: 8, monthly: 12). Excludes `tank/data/frigate` and `tank/media/downloads`.

- **Script version note**: Use `aws_backup/aws_backup.pl` (Jan 2025, newer) rather than root-level `aws_backup.pl` (Jul 2021, older)

- **Note**: All automation is user-level (not system-level), making migration straightforward. Scripts are located in `/home/$USER/scripts/` and can be copied directly (or cloned if git repos), but Perl module dependencies and AWS configuration must be verified on Arch.

### Temp Pool Contents

Output will be saved to `static/census/arch-hypervisor-migration/<date>-temp-pool-info.txt`.

```bash
# What's in the temp pool?
zfs list temp
du -sh /temp/*
find /temp -type f -exec ls -lh {} \; | head -20
zfs get all temp
```

## Phase 2: Full System Backup

TODO: review process. Doesn't seem to be ideal. May want to consider the approach used by my Arch Router that uses `cp -a` (IIRC) to avoid redundant copies. FWIW, having ZFS snapshots and offsite backup of /tank/backup might make versioning unnecessary.

Before making any changes, create a complete backup of the system to `/tank/backup`. This should become a regular automated process on the new system.

### Backup Contents

- System configuration files (`/etc/`)
- User home directories
- Docker data volumes and configurations
- VM XML definitions (already exported in Phase 1)
- Package lists
- Service configurations
- SSH keys and authorized_keys

### Backup Process

```bash
# Create backup directory with timestamp
BACKUP_DIR="/tank/backup/hypervisor-system-backup-$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# System configuration
sudo tar -czf "$BACKUP_DIR/etc-backup.tar.gz" /etc/

# Home directories
sudo tar -czf "$BACKUP_DIR/home-backup.tar.gz" /home/

# Docker volumes and configs
docker ps -a --format "{{.Names}}" > "$BACKUP_DIR/docker-containers.txt"
docker images > "$BACKUP_DIR/docker-images.txt"
sudo tar -czf "$BACKUP_DIR/docker-volumes.tar.gz" /var/lib/docker/volumes/

# Package list (already done in Phase 1, but verify)
cp /tank/backup/ubuntu-packages.txt "$BACKUP_DIR/"

# VM XMLs (already exported in Phase 1)
cp /tank/backup/vm-*.xml "$BACKUP_DIR/" 2>/dev/null || true

# Verify backup
ls -lh "$BACKUP_DIR"
```

## Phase 3: Temp Pool Data Migration

Before repurposing the 1TB temp pool drive, migrate its contents.

### Identify and Migrate Temp Pool Data

```bash
# Review what's in temp pool
zfs list -r temp
du -sh /temp/*

# Migrate to appropriate location (likely /tank/backup or /tank/temp-migrated)
# Adjust based on what's actually there
sudo rsync -av /temp/ /tank/backup/temp-migration/

# Verify migration
diff -r /temp/ /tank/backup/temp-migration/

# Export temp pool
sudo zpool export temp

# Verify drive is free
lsblk
```

## Phase 4: Partitioning Strategy for 1TB Drive

The 1TB drive needs to be partitioned optimally:
- **OS partition**: 250GB for Arch Linux (plenty of room for growth)
  - This needs to be reviewed. Advice online has led me astray here in the past and it is very painful. My current system is using 108GB out of its allotted 185GB, suggesting >100GB is crucial.
    - Some (most?) of the current system's use might be user data that could be moved to a HOME partition down the road, but it's best to keep simple, I think
- **Remaining space**: ~750GB to be determined based on needs
  - Option 1: Additional ZFS pool for fast storage
  - Option 2: Extended temp/download space
  - Option 3: Swap partition (if needed)
  - Option 4: Reserved for future use

### Partition Layout (to be finalized)

```
/dev/sdX1: 250GB - Arch Linux OS (ext4 or btrfs)
/dev/sdX2: 750GB - TBD (possibly new ZFS pool or extended temp space)
```

## Phase 5: Side-by-Side Arch Installation

Install Arch Linux on the 1TB drive while keeping Ubuntu 20.04 fully functional.

### Preparation

- Create bootable Arch USB
- Boot from USB
- Partition 1TB drive according to Phase 4 plan
- Install Arch Linux base system
- Configure dual boot (GRUB or systemd-boot)

### Arch Base System Setup

- Install base packages
- Configure ZFS support (`zfs-dkms` or `zfs-linux`)
- Set up network configuration
- Create user accounts
- Configure SSH access
- Import existing ZFS pools (read-only initially for safety)

## Phase 6: Service Migration

Migrate services one at a time, testing each before moving to the next.

### Docker and Containers

- Install Docker on Arch
- Restore Docker volumes from backup
- Configure containers (Jellyfin, Sonarr, Radarr, HomeAssistant, Deluge)
- Test each service
- Verify port mappings and network access

### Virtualization Setup

- Install KVM/QEMU/libvirt packages
- Configure IOMMU/VFIO (same kernel parameters as Ubuntu)
- **Important**: Mixed GPU vendors (NVIDIA + AMD) avoid GRUB blacklisting issues that occur with same-vendor GPUs
- Import VM XML definitions
- Test GPU passthrough on both VMs
- Verify VM networking and performance
- **Note**: No CPU pinning or huge pages unless performance testing shows they're needed

### ZFS Automation

- Set up ZFS auto-snapshots (systemd timer or cron)
- Configure weekly scrubs
- Verify snapshot retention policies

### AWS Glacier Backups

- Install aws-cli
- Restore backup scripts
- Test backup process
- Verify encryption and Glacier transition

## Phase 7: Automated Full System Backup Setup


Implement regular automated full system backups to `/tank/backup`.

### Backup Script

Create a script that:
- Backs up `/etc/`, `/home/`, Docker volumes, VM configs
  - Should be able to start from Phase 2 script above
    - Don't just keep copying the ubuntu packages list. That is just to setup the new Arch Hypervisor with the necessary packages. For Arch Hypervisor backup, generate new list of installed packages in the running system.
    - Likewise, regenerate VM XMLs at each backup. They can change and keeping the static version from before creation doesn't make sense.
- Uses timestamped directories - TODO: consider whether ZFS snapshots makes this - and next step - unnecessary
- Implements retention policy (e.g., keep last 4 weekly backups)
- Logs backup status
- Sends notifications on failure

### Automation

- Set up systemd timer for weekly backups
- Or use cron for scheduled backups
- Document retention and cleanup procedures

## Phase 8: Testing and Validation

Thoroughly test the new system before cutover.

### Service Testing

- Verify all Docker containers are running and accessible
- Test VM performance and GPU passthrough
- Verify ZFS pools are functioning correctly
- Test network connectivity and bridge networking
- Verify all services are accessible at their expected URLs

### Backup Testing

- Test ZFS snapshot automation
- Test AWS Glacier backup process
- Test full system backup script
- Verify backup restoration process

### Performance Validation

- Compare VM performance to Ubuntu system
- Monitor system resources
- Verify no regressions

## Phase 9: Cutover

Once everything is tested and validated:

1. Final data sync if needed
2. Update boot order to default to Arch
3. Keep Ubuntu 20.04 as fallback option
4. Monitor system for a period before considering Ubuntu removal

## Post-Migration Tasks

- Document any differences from Ubuntu setup
- Update any documentation with Arch-specific notes
- Set up monitoring/alerting for critical services
- Schedule regular review of backup logs
- Consider removing Ubuntu partition after extended successful operation

## Lessons Learned

(To be filled in after migration)

## References

- Previous blog posts on this system:
  - [Initial Ryzen Setup]({{< ref "initial_ryzen_steps" >}})
  - [ZFS Configuration]({{< ref "zfs" >}})
  - [Windows VM Creation]({{< ref "creating_windows_guest_vm" >}})
  - [Linux VM Creation]({{< ref "creating_linux_guest_vm" >}})
  - [Performance Tuning]({{< ref "perf_tuning_vms" >}})
  - [Offsite Backup]({{< ref "offsite_backup" >}})
