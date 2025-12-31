#!/bin/bash
# Hypervisor System Backup Script
# Creates a full system backup using rsync (similar to Arch Router backup approach)
# Based on Phase 2 of arch-hypervisor-plan.md

set -euo pipefail

# Configuration
BACKUP_BASE="/tank/backup"
BACKUP_DIR="${BACKUP_BASE}/hypervisor-system-backup-$(date +%Y%m%d)"
LOG_FILE="${BACKUP_DIR}/backup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

# Check if running as root (rsync needs root for full system backup)
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}[ERROR]${NC} This script must be run as root (use sudo)" >&2
    exit 1
fi

# Create backup directory FIRST (before any file logging)
echo "Creating backup directory: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR" || {
    echo -e "${RED}[ERROR]${NC} Failed to create backup directory" >&2
    exit 1
}

# Start logging
log "Starting full system backup"
log "Backup destination: $BACKUP_DIR"

# Full system backup (exclude virtual filesystems, mounted ZFS pools, and unnecessary files)
log "Starting rsync backup..."
rsync -aAXHv --delete \
  --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found","/tank/*","/temp/*","/downloads/*","/swap.img","/var/cache/*","/var/tmp/*","/var/log/*","/var/lib/apt/lists/*","/var/lib/systemd/coredump/*"} \
  / "$BACKUP_DIR/" 2>&1 | tee -a "$LOG_FILE" "${BACKUP_DIR}/rsync.log"

RSYNC_EXIT=${PIPESTATUS[0]}
if [ $RSYNC_EXIT -eq 0 ]; then
    log "rsync backup completed successfully"
else
    error "rsync backup completed with exit code $RSYNC_EXIT"
    warn "Backup may be incomplete - check logs"
fi

# Capture running system state (requires running system)
log "Capturing Docker container and image information..."
if command -v docker &> /dev/null; then
    docker ps -a --format "{{.Names}}" > "$BACKUP_DIR/docker-containers.txt" 2>&1 || warn "Failed to capture Docker containers list"
    docker images > "$BACKUP_DIR/docker-images.txt" 2>&1 || warn "Failed to capture Docker images list"
    log "Docker information captured"
else
    warn "Docker not found - skipping Docker state capture"
fi

# Copy Phase 1 outputs for convenience (already in /tank/backup)
log "Copying Phase 1 census outputs..."
if [ -f "${BACKUP_BASE}/ubuntu-packages.txt" ]; then
    cp "${BACKUP_BASE}/ubuntu-packages.txt" "$BACKUP_DIR/" && log "Copied package list"
else
    warn "Package list not found at ${BACKUP_BASE}/ubuntu-packages.txt"
fi

if ls "${BACKUP_BASE}"/vm-*.xml 1> /dev/null 2>&1; then
    cp "${BACKUP_BASE}"/vm-*.xml "$BACKUP_DIR/" && log "Copied VM XML definitions"
else
    warn "No VM XML files found in ${BACKUP_BASE}/"
fi

# Verify backup
log "Backup verification:"
log "Backup directory size:"
du -sh "$BACKUP_DIR" | tee -a "$LOG_FILE"

log "Backup directory contents:"
ls -lh "$BACKUP_DIR" | tee -a "$LOG_FILE"

# Summary
log "Backup completed: $BACKUP_DIR"
log "Log file: $LOG_FILE"
log "rsync log: ${BACKUP_DIR}/rsync.log"

if [ $RSYNC_EXIT -eq 0 ]; then
    log "Backup completed successfully!"
    exit 0
else
    error "Backup completed with warnings - please review logs"
    exit 1
fi

