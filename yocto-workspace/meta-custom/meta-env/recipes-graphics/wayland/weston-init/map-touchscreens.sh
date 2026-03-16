#!/bin/bash
# Map Waveshare touchscreens to correct HDMI outputs
# This script runs before Weston starts

# Wait for devices to settle
sleep 2

# Find touch device IDs
# Adjust the grep pattern based on actual device name from 'libinput list-devices'
TOUCH1_ID=$(libinput list-devices | grep -A 1 "ILITEK" | grep "event" | head -n1 | awk '{print $NF}')
TOUCH2_ID=$(libinput list-devices | grep -A 1 "ILITEK" | grep "event" | tail -n1 | awk '{print $NF}')

# Log device IDs for debugging
echo "Touch device 1: $TOUCH1_ID"
echo "Touch device 2: $TOUCH2_ID"

# Note: Actual mapping will be done by Weston based on physical proximity
# This script is mainly for debugging and verification

# Export environment variables that Weston might use
export LIBINPUT_CALIBRATION_MATRIX_0="1 0 0 0 1 0"
export LIBINPUT_CALIBRATION_MATRIX_1="1 0 0 0 1 0"
