#!/bin/bash
# Quick fix for the most likely boot hang issues
# Run this, rebuild, and deploy

echo "=== Quick Fix for Boot Hang Issues ==="
echo

WORKSPACE_ROOT="/home/seame/DES_Head-Unit/yocto-workspace"

# Fix 1: Remove EnvironmentFile dependency from weston.service
echo "Fix 1: Commenting out EnvironmentFile in weston.service..."
WESTON_SVC="$WORKSPACE_ROOT/meta-custom/meta-env/recipes-graphics/wayland/weston-init/systemd/weston.service"

if [ -f "$WESTON_SVC" ]; then
    # Comment out EnvironmentFile if it's not already commented
    sed -i 's/^EnvironmentFile=/#EnvironmentFile=/' "$WESTON_SVC"
    echo "  ✓ EnvironmentFile commented out"
else
    echo "  ✗ weston.service not found!"
fi

# Fix 2: Change plymouth quit to use --wait instead of --retain-splash
echo
echo "Fix 2: Changing plymouth-quit-timer to use --wait..."
PLYMOUTH_TIMER="$WORKSPACE_ROOT/meta-custom/meta-env/recipes-core/plymouth/plymouth/plymouth-quit-timer.service"

if [ -f "$PLYMOUTH_TIMER" ]; then
    sed -i "s|plymouth quit --retain-splash|plymouth quit --wait|g" "$PLYMOUTH_TIMER"
    echo "  ✓ Plymouth timer updated to use --wait"
else
    echo "  ✗ plymouth-quit-timer.service not found!"
fi

# Fix 3: Make Weston wait for plymouth-quit-timer
echo
echo "Fix 3: Adding plymouth-quit-timer dependency to weston.service..."

if [ -f "$WESTON_SVC" ]; then
    # Check if After line already contains plymouth-quit-timer
    if grep -q "plymouth-quit-timer.service" "$WESTON_SVC"; then
        echo "  ✓ Already has plymouth-quit-timer dependency"
    else
        # Add plymouth-quit-timer.service to the After line
        sed -i '/^After=.*dbus.socket/ s/$/ plymouth-quit-timer.service/' "$WESTON_SVC"
        echo "  ✓ Added plymouth-quit-timer dependency"
    fi
fi

# Fix 4: Create /etc/default/weston file for the image
echo
echo "Fix 4: Creating weston-default file..."
WESTON_DEFAULT_FILE="$WORKSPACE_ROOT/meta-custom/meta-env/recipes-graphics/wayland/weston-init/weston-default"

cat > "$WESTON_DEFAULT_FILE" << 'EOF'
# Weston compositor environment variables
# All configuration is in /etc/xdg/weston/weston.ini
# This file is optional but prevents EnvironmentFile errors
EOF

echo "  ✓ Created weston-default"

# Fix 5: Update weston-init.bbappend to install weston-default
echo
echo "Fix 5: Updating weston-init.bbappend..."
WESTON_BBAPPEND="$WORKSPACE_ROOT/meta-custom/meta-env/recipes-graphics/wayland/weston-init.bbappend"

if [ -f "$WESTON_BBAPPEND" ]; then
    # Check if weston-default is already in SRC_URI
    if ! grep -q "file://weston-default" "$WESTON_BBAPPEND"; then
        # Add weston-default to SRC_URI
        sed -i '/^SRC_URI += "/a\    file://weston-default \\' "$WESTON_BBAPPEND"
    fi

    # Check if do_install:append already installs weston-default
    if ! grep -q "install.*weston-default.*\${sysconfdir}/default/weston" "$WESTON_BBAPPEND"; then
        # Add installation commands
        cat >> "$WESTON_BBAPPEND" << 'EOF'

# Install weston environment defaults
do_install:append() {
    install -d ${D}${sysconfdir}/default
    if [ -f ${WORKDIR}/weston-default ]; then
        install -m 0644 ${WORKDIR}/weston-default ${D}${sysconfdir}/default/weston
    fi
}
EOF
    fi

    echo "  ✓ Updated weston-init.bbappend"
else
    echo "  ✗ weston-init.bbappend not found!"
fi

# Show what we changed
echo
echo "=== Changes Summary ==="
echo "1. EnvironmentFile commented out in weston.service"
echo "2. Plymouth quit changed to use --wait for complete shutdown"
echo "3. Weston now waits for plymouth-quit-timer"
echo "4. Created /etc/default/weston file"
echo "5. Updated bbappend to install weston-default"

echo
echo "=== Current weston.service After= line ==="
grep "^After=" "$WESTON_SVC"

echo
echo "=== Current plymouth-quit-timer ExecStart ==="
grep "ExecStart=" "$PLYMOUTH_TIMER"

echo
echo "=== Next Steps ==="
echo "1. Review the changes above"
echo "2. Clean and rebuild:"
echo "   cd yocto-workspace"
echo "   . poky/oe-init-build-env build-des"
echo "   bitbake -c cleansstate weston-init plymouth"
echo "   bitbake des-image"
echo "3. Deploy to SD card"
echo "4. Test boot sequence"
