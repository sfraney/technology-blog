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
    
#    echo "--- AWS Backup Scripts (s3) ---"
#    grep -r "aws.*s3" /home 2>/dev/null || echo "No AWS S3 references found in /home"
#    echo ""
    
#    echo "--- AWS Backup Scripts (glacier) ---"
#    grep -r "glacier" /home 2>/dev/null || echo "No Glacier references found in /home"
#    echo ""
    
    echo "--- Known Scripts Directory Structure ---"
    # Find primary user (UID 1000) or use current user
    PRIMARY_USER=$(getent passwd 1000 | cut -d: -f1 2>/dev/null || echo "$USER")
    SCRIPTS_DIR="/home/$PRIMARY_USER/scripts"

    if [ -d "$SCRIPTS_DIR" ]; then
        echo "Scripts directory: $SCRIPTS_DIR"
        ls -laR "$SCRIPTS_DIR" 2>/dev/null || echo "Could not list $SCRIPTS_DIR"
    else
        echo "Scripts directory not found: $SCRIPTS_DIR"
    fi
    echo ""
    
    echo "--- Router Backup Script (archrouter_full_backup.sh) ---"
    if [ -f "$SCRIPTS_DIR/archrouter_full_backup.sh" ]; then
        cat "$SCRIPTS_DIR/archrouter_full_backup.sh"
    else
        echo "Script not found: $SCRIPTS_DIR/archrouter_full_backup.sh"
    fi
    echo ""
    
    echo "--- ZFS Auto-Snapshot Script (perl-zfs-auto-snap/zfs-auto-snap.pl) ---"
    if [ -f "$SCRIPTS_DIR/perl-zfs-auto-snap/zfs-auto-snap.pl" ]; then
        head -50 "$SCRIPTS_DIR/perl-zfs-auto-snap/zfs-auto-snap.pl"
        echo ""
        echo "--- Perl Dependencies (zfs-auto-snap.pl) ---"
        head -20 "$SCRIPTS_DIR/perl-zfs-auto-snap/zfs-auto-snap.pl" | grep -E "^use|^require" || echo "No Perl dependencies found in first 20 lines"
    else
        echo "Script not found: $SCRIPTS_DIR/perl-zfs-auto-snap/zfs-auto-snap.pl"
    fi
    echo ""
    
    echo "--- AWS Backup Script (aws_backup/aws_backup.pl) ---"
    if [ -f "$SCRIPTS_DIR/aws_backup/aws_backup.pl" ]; then
        head -50 "$SCRIPTS_DIR/aws_backup/aws_backup.pl"
        echo ""
        echo "--- Perl Dependencies (aws_backup.pl) ---"
        head -20 "$SCRIPTS_DIR/aws_backup/aws_backup.pl" | grep -E "^use|^require|import" || echo "No Perl dependencies found in first 20 lines"
    else
        echo "Script not found: $SCRIPTS_DIR/aws_backup/aws_backup.pl"
    fi
} | tee "$OUTPUT_FILE"

echo "Backup scripts inventory saved to: $OUTPUT_FILE"

