#!/bin/bash
# VM Configuration Census Script
# VM XML exports will be saved to: /tank/backup/vm-<vm-name>.xml
# Other output will be saved to: static/census/arch-hypervisor-migration/<date>-vm-config.txt

OUTPUT_FILE="static/census/arch-hypervisor-migration/$(date +%Y-%m-%d)-vm-config.txt"
BACKUP_DIR="/tank/backup"

mkdir -p "$BACKUP_DIR"

{
    echo "=== VM Configuration - $(date) ==="
    echo ""
    
    echo "--- List All VMs ---"
    virsh list --all
    echo ""
    
    echo "--- Exporting VM XML Configurations ---"
    for vm in $(virsh list --all --name); do
        if [ -n "$vm" ]; then
            echo "Exporting VM: $vm"
            virsh dumpxml "$vm" > "$BACKUP_DIR/vm-$vm.xml" 2>&1
            if [ $? -eq 0 ]; then
                echo "  Successfully exported to $BACKUP_DIR/vm-$vm.xml"
            else
                echo "  Failed to export $vm"
            fi
        fi
    done
    echo ""
    
    echo "--- IOMMU Groups ---"
    for d in /sys/kernel/iommu_groups/*/devices/*; do
        n=${d#*/iommu_groups/*}; n=${n%%/*}
        printf 'IOMMU Group %s ' "$n"
        lspci -nns "${d##*/}"
    done
    echo ""
    
    echo "--- PCI Devices ---"
    lspci -nn
    echo ""
    
    echo "--- GPU Information (VGA) ---"
    lspci -nn | grep -i vga
    echo ""
    
    echo "--- GPU Information (3D/Display) ---"
    lspci -nn | grep -i "3d\|display"
    echo ""
    
    echo "--- GPU Information (NVIDIA/AMD/Radeon) ---"
    lspci -nn | grep -E "(NVIDIA|AMD|Radeon)"
} | tee "$OUTPUT_FILE"

echo "VM configuration saved to: $OUTPUT_FILE"
echo "VM XML files saved to: $BACKUP_DIR/"

