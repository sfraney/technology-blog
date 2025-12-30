#!/bin/bash
# Network Configuration Census Script
# Output will be saved to: static/census/arch-hypervisor-migration/<date>-network-config.txt

OUTPUT_FILE="static/census/arch-hypervisor-migration/$(date +%Y-%m-%d)-network-config.txt"

{
    echo "=== Network Configuration - $(date) ==="
    echo ""
    
    echo "--- Network Interfaces ---"
    ip addr show
    echo ""
    echo "--- Alternative (ifconfig) ---"
    ifconfig -a 2>/dev/null || echo "ifconfig not available"
    echo ""
    
    echo "--- Network Configuration Files ---"
    if [ -d /etc/netplan ]; then
        ls -la /etc/netplan/
        echo ""
        cat /etc/netplan/*.yaml
    else
        echo "Netplan not found, checking /etc/network/interfaces"
        cat /etc/network/interfaces 2>/dev/null || echo "No network/interfaces file found"
    fi
    echo ""
    
    echo "--- Bridge Configuration ---"
    brctl show 2>/dev/null || echo "brctl not available"
    echo ""
    ip link show type bridge
    echo ""
    
    echo "--- Firewall Rules ---"
    if command -v ufw >/dev/null 2>&1; then
        sudo ufw status verbose
    else
        echo "UFW not available, showing iptables:"
        sudo iptables -L -v -n
        echo ""
        sudo iptables -t nat -L -v -n
    fi
    echo ""
    
    echo "--- Routing ---"
    ip route show
} | tee "$OUTPUT_FILE"

echo "Network configuration saved to: $OUTPUT_FILE"

