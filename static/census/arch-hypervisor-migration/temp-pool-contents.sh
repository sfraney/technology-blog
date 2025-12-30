#!/bin/bash
# Temp Pool Contents Census Script
# Output will be saved to: static/census/arch-hypervisor-migration/<date>-temp-pool-contents.txt

OUTPUT_FILE="static/census/arch-hypervisor-migration/$(date +%Y-%m-%d)-temp-pool-contents.txt"

{
    echo "=== Temp Pool Contents - $(date) ==="
    echo ""
    
    echo "--- ZFS List (temp pool) ---"
    zfs list temp
    echo ""
    
    echo "--- Directory Sizes in /temp ---"
    du -sh /temp/* 2>/dev/null || echo "No contents in /temp or pool not mounted"
    echo ""
    
    echo "--- Sample Files in /temp (first 20) ---"
    find /temp -type f -exec ls -lh {} \; 2>/dev/null | head -20 || echo "No files found or pool not mounted"
    echo ""
    
    echo "--- ZFS Properties (temp pool) ---"
    zfs get all temp
} | tee "$OUTPUT_FILE"

echo "Temp pool contents saved to: $OUTPUT_FILE"

