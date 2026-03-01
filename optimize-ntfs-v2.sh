#!/bin/bash

# NTFS Performance Optimization Script v2 (Balanced)
# Author: Antigravity
# Date: 2026-02-28

set -e

# Configuration
UDEV_RULE_FILE="99-ntfs-performance.rules"
UDISKS_CONF_FILE="mount_options.conf"
UDEV_DEST="/etc/udev/rules.d/99-ntfs-performance.rules"
UDISKS_DEST="/etc/udisks2/mount_options.conf"
STATE_FILE="/home/sen/Documents/ntfs-tweaks/ntfs_optimization_v2_state.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting Balanced NTFS Performance Optimization (v2)...${NC}"

# 1. Root check
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script must be run as root${NC}" 
   exit 1
fi

# 2. Benchmark Function
run_benchmark() {
    local mount_point=$1
    local label=$2
    local test_file="${mount_point}/.ntfs_perf_test"
    
    echo -e "\n${BLUE}--- Performance Test: $label ---${NC}"
    
    # Sequential Read (100MB)
    echo -n "Sequential Read (100MB): "
    if [ -f "$test_file" ]; then
        # Use existing file if possible to test read
        timeout 30s dd if="$test_file" of=/dev/null bs=1M count=100 2>&1 | grep -oE '[0-9.]+ [MG]B/s' || echo "Timed out"
    else
        echo "N/A (No test file)"
    fi

    # Random Write (4KB x 100)
    echo -n "Random-style Write (4KB x 100): "
    timeout 30s dd if=/dev/urandom of="$test_file" bs=4k count=100 oflag=dsync conv=notrunc 2>&1 | grep -oE '[0-9.]+ [kMG]B/s' || echo "Timed out"
    
    rm -f "$test_file"
}

# 3. Save Current State
save_state() {
    echo -e "Saving current configuration state to ${GREEN}$STATE_FILE${NC}..."
    local mounted_info=$(findmnt -t ntfs,ntfs3,fuse.ntfs-3g -J || echo "{}")
    echo "$mounted_info" > "$STATE_FILE"
}

# 4. Process Disks
echo "Identifying mounted NTFS disks..."
MOUNTED_DISKS=$(findmnt -t ntfs,ntfs3,fuse.ntfs-3g,fuseblk -n -o SOURCE,TARGET,FSTYPE || true)
echo "Debug: MOUNTED_DISKS content: [$MOUNTED_DISKS]"

if [ -n "$MOUNTED_DISKS" ]; then
    save_state
    
    echo "$MOUNTED_DISKS" | while read -r SOURCE TARGET FSTYPE; do
        echo "Debug: Processing row: SOURCE=[$SOURCE] TARGET=[$TARGET] FSTYPE=[$FSTYPE]"
        
        # Verify it's actually NTFS if FSTYPE is fuseblk
        if [ "$FSTYPE" == "fuseblk" ]; then
            REAL_FSTYPE=$(lsblk -no FSTYPE "$SOURCE" | head -n 1)
            echo "Debug: REAL_FSTYPE identification: [$REAL_FSTYPE]"
            if [[ ! "$REAL_FSTYPE" =~ [Nn][Tt][Ff][Ss] ]]; then
                echo "Debug: Skipping non-NTFS disk: $SOURCE ($REAL_FSTYPE)"
                continue
            fi
        fi
        
        echo -e "\n${YELLOW}Processing ${GREEN}$SOURCE${NC} (currently ${FSTYPE})...${NC}"
        
        # Pre-optimization benchmark
        run_benchmark "$TARGET" "PRE-OPTIMIZATION"

        # Optimization
        echo -e "Applying optimizations to ${GREEN}$SOURCE${NC}..."
        
        # Unmount
        umount "$TARGET" || { echo -e "${RED}Failed to unmount $TARGET. Skipping...${NC}"; continue; }
        
        # ntfsfix
        if command -v ntfsfix >/dev/null; then
            echo -e "Running ${GREEN}ntfsfix${NC}..."
            ntfsfix -d "$SOURCE"
        fi
        
        # Remount with ntfs3 and balanced options
        echo -e "Remounting with ${GREEN}ntfs3${NC}, prealloc, async..."
        mkdir -p "$TARGET"
        mount -t ntfs3 -o noatime,prealloc,async,windows_names "$SOURCE" "$TARGET"
        
        # Set Read-Ahead
        DEVICE=$(echo "$SOURCE" | sed 's/[0-9]*$//')
        echo -e "Setting Read-Ahead for ${GREEN}$DEVICE${NC} to 4096KB..."
        blockdev --setra 4096 "$DEVICE"
        
        # Post-optimization benchmark
        run_benchmark "$TARGET" "POST-OPTIMIZATION"
    done
fi

# 5. Apply Permanent Configs
echo -e "\n${YELLOW}Applying permanent configuration files...${NC}"
cp "99-ntfs-performance.rules" "$UDEV_DEST"
udevadm control --reload-rules && udevadm trigger

mkdir -p /etc/udisks2
cp "mount_options.conf" "$UDISKS_DEST"

# 6. Update fstab
if grep -q "ntfs" /etc/fstab; then
    echo -e "Updating /etc/fstab to use ntfs3...${NC}"
    sed -i.bak -E 's/(ntfs|fuse\.ntfs-3g)/ntfs3/g' /etc/fstab
    echo -e "Backup created at /etc/fstab.bak"
fi

echo -e "\n${GREEN}Balanced NTFS Optimization v2 Complete!${NC}"
echo -e "System is now configured for high-speed reads (via read-ahead) and usable random writes (via ntfs3+prealloc)."
