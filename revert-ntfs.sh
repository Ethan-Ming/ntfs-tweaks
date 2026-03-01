#!/bin/bash

# NTFS Optimization Revert Script
# Author: Antigravity
# Date: 2026-02-28

set -e

# Configuration
UDEV_DEST="/etc/udev/rules.d/99-ntfs-performance.rules"
UDISKS_DEST="/etc/udisks2/mount_options.conf"
FSTAB_BAK="/etc/fstab.bak"
FSTAB="/etc/fstab"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting NTFS Optimization Revert...${NC}"

# 1. Root check
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

# 2. Remove configuration files
if [ -f "$UDEV_DEST" ]; then
    echo -e "Removing udev rule: ${GREEN}$UDEV_DEST${NC}"
    rm "$UDEV_DEST"
    udevadm control --reload-rules && udevadm trigger
fi

if [ -f "$UDISKS_DEST" ]; then
    echo -e "Removing udisks2 config: ${GREEN}$UDISKS_DEST${NC}"
    rm "$UDISKS_DEST"
fi

# 3. Restore fstab
if [ -f "$FSTAB_BAK" ]; then
    echo -e "Restoring fstab from backup: ${GREEN}$FSTAB_BAK${NC}"
    mv "$FSTAB_BAK" "$FSTAB"
else
    echo -e "${YELLOW}No fstab backup found. Manual check of /etc/fstab may be needed if it was modified.${NC}"
fi

# 4. Remount existing NTFS partitions to defaults
echo -e "Searching for currently mounted NTFS disks..."
# We search for ntfs3, ntfsplus, and fuse.ntfs-3g to be sure we catch them all
MOUNTED_NTFS=$(findmnt -t ntfs,ntfs3,ntfsplus,fuse.ntfs-3g -n -o SOURCE,TARGET,FSTYPE || true)

if [ -n "$MOUNTED_NTFS" ]; then
    echo -e "${YELLOW}Found mounted NTFS partitions. Attempting to revert to defaults...${NC}"
    echo "$MOUNTED_NTFS" | while read -r SOURCE TARGET FSTYPE; do
        echo -e "Reverting ${GREEN}$SOURCE${NC} mounted at ${GREEN}$TARGET${NC}..."
        
        # Unmount
        umount "$TARGET" || { echo -e "${RED}Failed to unmount $TARGET. Skipping...${NC}"; continue; }
        
        # Remount with defaults (letting the system decide the driver)
        echo -e "Remounting $SOURCE to $TARGET with default options..."
        mount "$SOURCE" "$TARGET" || mount -t ntfs-3g "$SOURCE" "$TARGET"
    done
fi

echo -e "\n${GREEN}NTFS Optimization Revert Complete!${NC}"
echo -e "System settings have been restored to their original state."
