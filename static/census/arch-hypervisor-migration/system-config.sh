#!/bin/bash
# System Configuration Census Script
# Package list will be saved to: /tank/backup/ubuntu-packages.txt
# Other output will be saved to: static/census/arch-hypervisor-migration/<date>-system-config.txt

OUTPUT_FILE="static/census/arch-hypervisor-migration/$(date +%Y-%m-%d)-system-config.txt"
PACKAGE_LIST="/tank/backup/ubuntu-packages.txt"

#mkdir -p "$(dirname "$PACKAGE_LIST")"

{
    echo "=== System Configuration - $(date) ==="
    echo ""
    
    echo "--- Boot Configuration (GRUB) ---"
    cat /etc/default/grub
    echo ""
    
    echo "--- GRUB Configuration ---"
    cat /boot/grub/grub.cfg
    echo ""
    
    echo "--- Installed Packages ---"
    echo "Package list being saved to: $PACKAGE_LIST"
    dpkg --get-selections | grep -v deinstall > "$PACKAGE_LIST"
    echo "Package count: $(wc -l < "$PACKAGE_LIST")"
    echo ""
    
    echo "--- User Accounts ---"
    cat /etc/passwd
    echo ""
    
    echo "--- Groups ---"
    cat /etc/group
    echo ""
    
    echo "--- Current User Info ---"
    id
    echo ""
    
    echo "--- SSH Configuration ---"
    echo "SSH config:"
    cat ~/.ssh/config 2>/dev/null || echo "No ~/.ssh/config file"
    echo ""
    echo "Authorized keys:"
    cat ~/.ssh/authorized_keys 2>/dev/null || echo "No ~/.ssh/authorized_keys file"
    echo ""
    echo "SSH directory listing:"
    ls -la ~/.ssh/ 2>/dev/null || echo "No ~/.ssh/ directory"
} | tee "$OUTPUT_FILE"

echo "System configuration saved to: $OUTPUT_FILE"
echo "Package list saved to: $PACKAGE_LIST"

