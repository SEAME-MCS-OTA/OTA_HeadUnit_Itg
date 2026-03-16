#!/bin/bash
# Rebuild Yocto image with A2DP Sink fixes

set -e

echo "=========================================="
echo "Rebuilding Yocto Image with A2DP Sink Fix"
echo "=========================================="

cd yocto-workspace

# Initialize build environment
source poky/oe-init-build-env build-des

# Clean BlueZ and PulseAudio to pick up new configurations
echo ""
echo "Cleaning BlueZ and PulseAudio..."
bitbake -c cleansstate bluez5
bitbake -c cleansstate pulseaudio

# Rebuild the DES image
echo ""
echo "Building des-image..."
bitbake des-image

echo ""
echo "✅ Build complete!"
echo ""
echo "Image location:"
echo "  yocto-workspace/build-des/tmp-glibc/deploy/images/raspberrypi4-64/"
echo ""
echo "Flash to SD card with:"
echo "  sudo dd if=des-image-raspberrypi4-64.rootfs.wic of=/dev/sdX bs=4M status=progress && sync"
echo ""
