# Add Seeed CAN-FD HAT v2 device tree overlay to kernel build
#
# This ensures the seeed-can-fd-hat-v2.dtbo overlay is built and included
# in the image at /boot/overlays/

KERNEL_DEVICETREE:append = " \
    overlays/seeed-can-fd-hat-v2.dtbo \
"
