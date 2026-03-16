#
# Instrument cluster CAN setup:
#  - SPI + I2C stay enabled so the controller stack can talk to the CAN HW.
#  - CAN overlay: Seeed CAN-FD HAT v2.0 (MCP2518FD on SPI0, CS0/CS1).
#

ENABLE_SPI_BUS = "1"
ENABLE_I2C = "1"

# Deploy the Seeed CAN-FD HAT v2 overlay to /boot/overlays/
RPI_KERNEL_DEVICETREE_OVERLAYS:append = " overlays/seeed-can-fd-hat-v2.dtbo"


# GPU Memory Configuration (optimized for dual display with power efficiency)
GPU_MEM = "128"

# Enable psplash boot logo support
ENABLE_UART = "1"

# Override VC4 dtoverlay to include noaudio parameter (prevents duplication)
VC4DTBO = "vc4-kms-v3d,noaudio"

# Dual HDMI Display Configuration for Head-Unit and Instrument Cluster
# HDMI-0: Head-Unit (1024x600), HDMI-1: Instrument Cluster (1024x600)
RPI_EXTRA_CONFIG:append = "\
\ndtoverlay=seeed-can-fd-hat-v2\
\nhdmi_drive:0=2\
\nhdmi_drive:1=2\
\nhdmi_force_hotplug:0=1\
\nhdmi_force_hotplug:1=1\
\nhdmi_group:0=2\
\nhdmi_group:1=2\
\nhdmi_mode:0=87\
\nhdmi_mode:1=87\
\nhdmi_cvt:0=1024 600 60 6 0 0 0\
\nhdmi_cvt:1=1024 600 60 6 0 0 0\
\nconfig_hdmi_boost:0=2\
\nconfig_hdmi_boost:1=2\
\ndisable_overscan=1\
\nmax_framebuffers=2\
\nenable_uart=1\
\ndisable_splash=1\
\n"
