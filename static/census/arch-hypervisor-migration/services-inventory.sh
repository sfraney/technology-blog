#!/bin/bash
# Services Inventory Census Script
# Output will be saved to: static/census/arch-hypervisor-migration/<date>-services-inventory.txt

OUTPUT_FILE="static/census/arch-hypervisor-migration/$(date +%Y-%m-%d)-services-inventory.txt"

{
    echo "=== Services Inventory - $(date) ==="
    echo ""
    
    echo "--- Systemd Services (running) ---"
    systemctl list-units --type=service --state=running
    echo ""
    
    echo "--- Systemd Services (enabled) ---"
    systemctl list-units --type=service --state=enabled
    echo ""
    
    echo "--- Systemd Timers (running) ---"
    systemctl list-units --type=timer --state=running
    echo ""
    
    echo "--- Docker Containers ---"
    docker ps -a
    echo ""
    
    echo "--- Docker Images ---"
    docker images
    echo ""
    
    echo "--- Docker Volumes ---"
    docker volume ls
    echo ""
    
    echo "--- Docker Directory Structure ---"
    ls -laR /home/sean/docker/ 2>/dev/null || echo "Directory /home/sean/docker/ not found"
    echo ""
    
    echo "--- Cron Jobs (user) ---"
    crontab -l 2>/dev/null || echo "No user crontab"
    echo ""
    
    echo "--- Cron Jobs (root) ---"
    sudo crontab -l 2>/dev/null || echo "No root crontab"
    echo ""
    
    echo "--- Cron Directories ---"
    ls -la /etc/cron.* 2>/dev/null || echo "No cron.* directories found"
    echo ""
    
    echo "--- System Crontab ---"
    cat /etc/crontab
} | tee "$OUTPUT_FILE"

echo "Services inventory saved to: $OUTPUT_FILE"

