#!/bin/bash
# Backup and Automation Scripts Census Script
# Output will be saved to: static/census/arch-hypervisor-migration/<date>-backup-scripts.txt

OUTPUT_FILE="static/census/arch-hypervisor-migration/$(date +%Y-%m-%d)-backup-scripts.txt"

{
    echo "=== Backup and Automation Scripts - $(date) ==="
    echo ""
    
    echo "--- Finding Backup Scripts in /home ---"
    find /home -name "*backup*" -type f 2>/dev/null
    echo ""
    
    echo "--- Finding Backup Scripts in /usr/local/bin ---"
    find /usr/local/bin -name "*backup*" -type f 2>/dev/null
    echo ""
    
    echo "--- Finding Backup Scripts in /etc ---"
    find /etc -name "*backup*" -type f 2>/dev/null
    echo ""
    
    echo "--- ZFS Snapshot Automation (systemd timers) ---"
    systemctl list-timers | grep -i snap
    echo ""
    
    echo "--- ZFS Snapshot Automation (cron) ---"
    grep -r "zfs.*snap" /etc/cron.* 2>/dev/null || echo "No ZFS snapshot entries in /etc/cron.*"
    echo ""
    
    echo "--- ZFS Snapshot Automation (user bin) ---"
    grep -r "zfs.*snap" /home/*/bin 2>/dev/null || echo "No ZFS snapshot scripts in /home/*/bin"
    echo ""
    
    echo "--- AWS Backup Scripts (s3) ---"
    grep -r "aws.*s3" /home 2>/dev/null || echo "No AWS S3 references found in /home"
    echo ""
    
    echo "--- AWS Backup Scripts (glacier) ---"
    grep -r "glacier" /home 2>/dev/null || echo "No Glacier references found in /home"
} | tee "$OUTPUT_FILE"

echo "Backup scripts inventory saved to: $OUTPUT_FILE"

