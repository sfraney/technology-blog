#!/bin/bash
# Storage Inventory Census Script
# Output will be saved to: static/census/arch-hypervisor-migration/2025-12-06-storage-inventory.txt

OUTPUT_FILE="static/census/arch-hypervisor-migration/2025-12-06-storage-inventory.txt"

{
    echo "=== Storage Inventory - $(date) ==="
    echo ""
    
    echo "--- Block Devices ---"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,UUID
    echo ""
    
    echo "--- ZFS Pool Status (all pools) ---"
    zpool status
    echo ""
    zpool status -v
    echo ""
    
    echo "--- Detailed ZFS Pool Information (tank) ---"
    zpool status tank
    echo ""
    zpool list -v
    echo ""
    
    echo "--- Filesystem Usage ---"
    df -h
    echo ""
    df -hT
    echo ""
    
    echo "--- Mount Points ---"
    mount | sort
    echo ""
    cat /etc/fstab
    echo ""
    
    echo "--- Disk Partitions ---"
    sudo fdisk -l
    echo ""
    lsblk -f
} | tee "$OUTPUT_FILE"

echo "Storage inventory saved to: $OUTPUT_FILE"

