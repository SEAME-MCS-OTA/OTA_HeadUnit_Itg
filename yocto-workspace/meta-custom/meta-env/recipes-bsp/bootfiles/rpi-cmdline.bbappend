# Minimal boot - NO PLYMOUTH
# Just serial console for debugging
#
# NOTE (A/B OTA): cmdline.txt is the slot source-of-truth in this repository.
# RAUC backend scripts switch rootfs by updating /boot/cmdline.txt root=
# between /dev/mmcblk0p2 (A) and /dev/mmcblk0p3 (B).
CMDLINE_SERIAL = "console=serial0,115200 console=tty1"
CMDLINE:append = " quiet loglevel=3"
