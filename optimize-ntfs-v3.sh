#!/bin/bash
# Balanced NTFS Optimization v3 (Removable/HDD)
# Optimized for sequential throughput and usable random writes.
# Includes Aggressive Sync (faster writeback) and I/O Scheduler tuning.

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

STATE_FILE="/home/sen/Documents/ntfs-tweaks/ntfs_optimization_v3_state.json"
SYSCTL_FILE="/etc/sysctl.d/99-ntfs-sync.conf"
UDEV_RULE="/etc/udev/rules.d/99-ntfs-performance.rules"

echo -e "${YELLOW}Starting Balanced NTFS Performance Optimization (v3)...${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}This script must be run as root${NC}"
    exit 1
fi

# 1. Save Current State
save_state() {
    echo -e "Saving current configuration state to ${GREEN}${STATE_FILE}${NC}..."
    findmnt -t ntfs,ntfs3,fuse.ntfs-3g,fuseblk -J -o SOURCE,TARGET,FSTYPE,OPTIONS > "$STATE_FILE"
}

# 2. Performance Benchmark Function
run_benchmark() {
    local target_dir=$1
    local label=$2
    
    echo -e "${BLUE}--- Performance Test: $label ---${NC}"
    
    # Create temp test file if target exists
    if [ -d "$target_dir" ]; then
        local test_file="$target_dir/ntfs_perf_test.tmp"
        
        # Sequential Read (Simulated with dd 100MB)
        # Note: We use iflag=direct to bypass some layers, or just standard for "perceived" speed
        echo -n "Sequential Read (100MB): "
        if dd if=/dev/urandom of="$test_file" bs=1M count=100 conv=fsync status=none 2>/dev/null; then
            # Measure read speed
            local read_speed=$(timeout 30s dd if="$test_file" of=/dev/null bs=1M count=100 2>&1 | grep -oE '[0-9.]+ [MG]B/s' || echo "Timed Out")
            echo "$read_speed"
        else
            echo "Write failed (Check space)"
        fi
        
        # Random-style Write (4KB x 100)
        # We use oflag=dsync to measure actual hardware commitment
        echo -n "Random-style Write (4KB x 100): "
        local write_speed=$(timeout 30s dd if=/dev/urandom of="$test_file" bs=4K count=100 oflag=dsync 2>&1 | grep -oE '[0-9.]+ [MG]B/s' || echo "Timed Out")
        echo "$write_speed"
        
        rm -f "$test_file"
    else
        echo "Target directory $target_dir not accessible."
    fi
}

# 3. Apply Permanent Configuration Files
apply_configs() {
    echo -e "\n${YELLOW}Applying permanent configuration files...${NC}"
    
    # Aggressive Sync (Sysctl)
    if [ -f "/home/sen/Documents/ntfs-tweaks/99-ntfs-sync.conf" ]; then
        cp "/home/sen/Documents/ntfs-tweaks/99-ntfs-sync.conf" "$SYSCTL_FILE"
        sysctl -p "$SYSCTL_FILE" >/dev/null
        echo -e "  - Aggressive Sync (Writeback) applied."
    fi
    
    # Udev Rule
    if [ -f "/home/sen/Documents/ntfs-tweaks/99-ntfs-performance.rules" ]; then
        cp "/home/sen/Documents/ntfs-tweaks/99-ntfs-performance.rules" "$UDEV_RULE"
        udevadm control --reload-rules && udevadm trigger
        echo -e "  - Udev Performance Rules (HDD/Removable) applied."
    fi
}

# 4. Process Mounted NTFS Disks
echo "Identifying mounted NTFS disks..."
MOUNTED_DISKS=$(findmnt -t ntfs,ntfs3,fuse.ntfs-3g,fuseblk -n -o SOURCE,TARGET,FSTYPE || true)

if [ -n "$MOUNTED_DISKS" ]; then
    save_state
    
    echo "$MOUNTED_DISKS" | while read -r SOURCE TARGET FSTYPE; do
        # Verify it's actually NTFS if FSTYPE is fuseblk
        if [ "$FSTYPE" == "fuseblk" ]; then
            REAL_FSTYPE=$(lsblk -no FSTYPE "$SOURCE" | head -n 1)
            if [[ ! "$REAL_FSTYPE" =~ [Nn][Tt][Ff][Ss] ]]; then
                continue
            fi
        fi

        # Check if disk is Removable OR Rotational (HDD)
        DISK=$(lsblk -no PKNAME "$SOURCE" | head -n 1)
        [ -z "$DISK" ] && DISK=$(echo "$SOURCE" | sed 's/[0-9]*//g') # Fallback
        IS_REMOVABLE=$(cat "/sys/block/$DISK/removable" 2>/dev/null || echo "0")
        IS_ROTATIONAL=$(cat "/sys/block/$DISK/queue/rotational" 2>/dev/null || echo "0")
        
        if [ "$IS_REMOVABLE" != "1" ] && [ "$IS_ROTATIONAL" != "1" ]; then
            echo -e "Skipping non-HDD/non-removable disk: $SOURCE"
            continue
        fi
        
        echo -e "\n${YELLOW}Processing ${GREEN}$SOURCE${NC} (Removable: $IS_REMOVABLE, Rotational: $IS_ROTATIONAL)...${NC}"
        
        # Pre-Optimization Bench
        run_benchmark "$TARGET" "PRE-OPTIMIZATION"
        
        # Apply Optimizations
        echo -e "Applying optimizations to ${GREEN}$SOURCE${NC}..."
        umount "$SOURCE" || true
        
        # ntfsfix to clear dirty bits
        echo -e "Running ${GREEN}ntfsfix${NC}..."
        ntfsfix -b -d "$SOURCE" >/dev/null || true
        
        # Remount with ntfs3 and balanced options
        echo -e "Remounting with ${GREEN}ntfs3${NC}, prealloc, async..."
        mkdir -p "$TARGET"
        mount -t ntfs3 -o noatime,prealloc,async,windows_names "$SOURCE" "$TARGET"
        
        # Set Read-Ahead and Scheduler immediately
        echo -e "Setting ${GREEN}4MB Read-Ahead${NC} and ${GREEN}bfq${NC} scheduler..."
        blockdev --setra 4096 "$SOURCE"
        echo "bfq" > "/sys/block/$DISK/queue/scheduler" 2>/dev/null || echo "mq-deadline" > "/sys/block/$DISK/queue/scheduler" 2>/dev/null || true
        
        # Post-Optimization Bench
        run_benchmark "$TARGET" "POST-OPTIMIZATION"
    done
else
    echo "No mounted NTFS disks found."
fi

apply_configs

echo -e "\n${GREEN}Balanced NTFS Optimization v3 Complete!${NC}"
echo "Targets: External USB Disks + Internal Mechanical HDDs."
echo "Features: bfq scheduler, 4MB Read-Ahead, Aggressive Sync (5s writeback)."
