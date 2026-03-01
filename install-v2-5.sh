#!/bin/bash
# install-v2-5.sh - NTFS Restoration (Byte-Limited Cache)
set -e
TWEAKS_DIR="$(cd "$(dirname "$0")" && pwd)"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

if [ "$EUID" -ne 0 ]; then echo -e "${RED}Run as root: sudo $0${NC}"; exit 1; fi

echo -e "${YELLOW}Installing NTFS Restoration v2.5 (Byte-Limited Cache)...${NC}"

# 1. Hardware Tuning (Udev)
cp "$TWEAKS_DIR/99-ntfs-performance.rules.v2.5" /etc/udev/rules.d/99-ntfs-performance.rules
udevadm control --reload-rules

# 2. Byte-Limited Caching (Sysctl)
cp "$TWEAKS_DIR/99-ntfs-v2-5.conf" /etc/sysctl.d/99-ntfs-v2-5.conf
sysctl -p /etc/sysctl.d/99-ntfs-v2-5.conf

# 3. Udisks2 Config (Permissions only, no dangerous flags)
mkdir -p /etc/udisks2
cat > /etc/udisks2/mount_options.conf << 'EOF'
[defaults]
ntfs_defaults=noatime,uid=1000,gid=1000,iocharset=utf8
ntfs3_defaults=noatime,uid=1000,gid=1000,iocharset=utf8
EOF
systemctl restart udisks2

echo -e "${GREEN}v2.5 Installed Successfully!${NC}"
echo -e "${YELLOW}ACTION: Please UNPLUG and RE-PLUG your USB disk.${NC}"
