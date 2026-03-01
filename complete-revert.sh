#!/bin/bash
# Complete NTFS Optimization Revert (Clean up all v1-v4 changes)
# Author: Antigravity

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

if [ "$EUID" -ne 0 ]; then echo -e "${RED}Run as root: sudo $0${NC}"; exit 1; fi

echo -e "${YELLOW}Starting Complete NTFS Optimization Revert...${NC}"

# 1. Remove sysctl config (Aggressive Sync)
if [ -f "/etc/sysctl.d/99-ntfs-sync.conf" ]; then
    echo "Removing /etc/sysctl.d/99-ntfs-sync.conf..."
    rm "/etc/sysctl.d/99-ntfs-sync.conf"
    # Restore defaults
    sysctl -w vm.dirty_expire_centisecs=3000 >/dev/null
    sysctl -w vm.dirty_writeback_centisecs=500 >/dev/null
fi

# 2. Remove udev rules and helper
if [ -f "/etc/udev/rules.d/99-ntfs-performance.rules" ]; then
    echo "Removing /etc/udev/rules.d/99-ntfs-performance.rules..."
    rm "/etc/udev/rules.d/99-ntfs-performance.rules"
fi

if [ -f "/usr/local/bin/ntfs-plug-helper.sh" ]; then
    echo "Removing /usr/local/bin/ntfs-plug-helper.sh..."
    rm "/usr/local/bin/ntfs-plug-helper.sh"
fi

udevadm control --reload-rules && udevadm trigger

# 3. Remove udisks2 config
if [ -f "/etc/udisks2/mount_options.conf" ]; then
    echo "Removing /etc/udisks2/mount_options.conf..."
    rm "/etc/udisks2/mount_options.conf"
    systemctl restart udisks2
fi

# 4. Remount existing NTFS partitions to defaults
echo "Searching for mounted NTFS partitions..."
# findmnt returns 0 if matches found
MOUNTED=$(findmnt -t ntfs,ntfs3,fuse.ntfs-3g,fuseblk -n -o SOURCE,TARGET || true)

if [ -n "$MOUNTED" ]; then
    echo "$MOUNTED" | while read -r SOURCE TARGET; do
        # Check if it's actually NTFS
        FSTYPE=$(lsblk -no FSTYPE "$SOURCE" | head -n1)
        if [[ "$FSTYPE" =~ [Nn][Tt][Ff][Ss] ]]; then
            echo "Reverting $SOURCE (currently at $TARGET) to default mount..."
            sync
            umount "$TARGET" || true
            # Clean up stale dirs
            [ -d "$TARGET" ] && rmdir "$TARGET" 2>/dev/null || true
            # Let the system mount it naturally (will likely use ntfs-3g/fuseblk by default)
            # We don't mount it manually here so the user can re-plug or have udisks handle it
        fi
    done
fi

echo -e "${GREEN}Complete Revert Finished!${NC}"
echo "System is back to stock NTFS behavior."
echo "Please UNPLUG and RE-PLUG your disk to ensure a clean mount state."
