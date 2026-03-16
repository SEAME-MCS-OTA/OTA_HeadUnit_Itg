#!/bin/bash
# Debug log collection script for Raspberry Pi
# Run this on the Raspberry Pi to collect diagnostic information

OUTPUT_DIR="/tmp/des-debug-logs-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUTPUT_DIR"

echo "Collecting debug logs to: $OUTPUT_DIR"

# System information
echo "=== System Info ===" > "$OUTPUT_DIR/system-info.log"
uname -a >> "$OUTPUT_DIR/system-info.log"
cat /proc/cpuinfo | grep Model >> "$OUTPUT_DIR/system-info.log"

# Systemd services status
echo "=== Systemd Services ===" > "$OUTPUT_DIR/services-status.log"
systemctl status headunit.service >> "$OUTPUT_DIR/services-status.log" 2>&1
echo -e "\n\n" >> "$OUTPUT_DIR/services-status.log"
systemctl status instrument-cluster.service >> "$OUTPUT_DIR/services-status.log" 2>&1

# Journal logs
echo "=== HeadUnit Journal ===" > "$OUTPUT_DIR/headunit-journal.log"
journalctl -u headunit.service -n 200 --no-pager >> "$OUTPUT_DIR/headunit-journal.log"

echo "=== Instrument Cluster Journal ===" > "$OUTPUT_DIR/cluster-journal.log"
journalctl -u instrument-cluster.service -n 200 --no-pager >> "$OUTPUT_DIR/cluster-journal.log"

# Boot logs
echo "=== Kernel Boot Messages ===" > "$OUTPUT_DIR/dmesg.log"
dmesg | tail -n 500 >> "$OUTPUT_DIR/dmesg.log"

# KMS configuration files
echo "=== KMS Configuration Files ===" > "$OUTPUT_DIR/kms-config.log"
ls -la /etc/*.json >> "$OUTPUT_DIR/kms-config.log" 2>&1
echo -e "\n--- headunit-kms.json ---" >> "$OUTPUT_DIR/kms-config.log"
cat /etc/headunit-kms.json >> "$OUTPUT_DIR/kms-config.log" 2>&1
echo -e "\n--- cluster-kms.json ---" >> "$OUTPUT_DIR/kms-config.log"
cat /etc/cluster-kms.json >> "$OUTPUT_DIR/kms-config.log" 2>&1

# Qt plugins
echo "=== Qt Plugins ===" > "$OUTPUT_DIR/qt-plugins.log"
ls -laR /usr/lib/qt6/plugins/platforms/ >> "$OUTPUT_DIR/qt-plugins.log" 2>&1
find /usr -name "*eglfs*" >> "$OUTPUT_DIR/qt-plugins.log" 2>&1

# Fonts
echo "=== Font Configuration ===" > "$OUTPUT_DIR/fonts.log"
fc-list >> "$OUTPUT_DIR/fonts.log" 2>&1
ls -laR /usr/share/fonts/ >> "$OUTPUT_DIR/fonts.log" 2>&1

# DRM/KMS information
echo "=== DRM/KMS Info ===" > "$OUTPUT_DIR/drm-info.log"
ls -la /dev/dri/ >> "$OUTPUT_DIR/drm-info.log" 2>&1
dmesg | grep -i drm >> "$OUTPUT_DIR/drm-info.log" 2>&1
dmesg | grep -i hdmi >> "$OUTPUT_DIR/drm-info.log" 2>&1

# Environment variables
echo "=== Environment (HeadUnit) ===" > "$OUTPUT_DIR/environment.log"
systemctl show headunit.service -p Environment >> "$OUTPUT_DIR/environment.log"
echo -e "\n=== Environment (Cluster) ===" >> "$OUTPUT_DIR/environment.log"
systemctl show instrument-cluster.service -p Environment >> "$OUTPUT_DIR/environment.log"

# Create tarball
cd /tmp
TARBALL="des-debug-logs-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$TARBALL" "$(basename $OUTPUT_DIR)"

echo ""
echo "✅ Logs collected successfully!"
echo "📦 Tarball: /tmp/$TARBALL"
echo ""
echo "Copy to development machine:"
echo "  scp root@raspberrypi:/tmp/$TARBALL /home/seame/DES_Head-Unit/logs/"
echo ""
