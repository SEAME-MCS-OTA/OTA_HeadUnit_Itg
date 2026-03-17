#!/bin/sh
# RAUC post-install handler: switches boot slot by updating /boot/cmdline.txt
# Called by RAUC after successful bundle installation.
set -e

BOOT_MOUNT="/boot"
CMDLINE_FILE="${BOOT_MOUNT}/cmdline.txt"
CMDLINE_PREV="${BOOT_MOUNT}/cmdline.prev.txt"
STATE_FILE="${BOOT_MOUNT}/rauc.state"
BOOT_ATTEMPTS=3
LOG_TAG="rauc-slot-switch"

log() { echo "${LOG_TAG}: $*"; logger -t "${LOG_TAG}" "$*" 2>/dev/null || true; }

# Ensure /boot is mounted rw
if ! mountpoint -q "${BOOT_MOUNT}"; then
    mount /boot || { log "ERROR: cannot mount /boot"; exit 1; }
fi
mount -o remount,rw "${BOOT_MOUNT}" 2>/dev/null || true

[ -f "${CMDLINE_FILE}" ] || { log "ERROR: ${CMDLINE_FILE} not found"; exit 1; }

# Determine current slot from cmdline.txt root= parameter
current_root=$(grep -o 'root=/dev/mmcblk0p[0-9]*' "${CMDLINE_FILE}" | sed 's/root=//' | head -n1)

case "${current_root}" in
    /dev/mmcblk0p2)
        current_slot="A"
        next_slot="B"
        next_root="/dev/mmcblk0p3"
        ;;
    /dev/mmcblk0p3)
        current_slot="B"
        next_slot="A"
        next_root="/dev/mmcblk0p2"
        ;;
    *)
        log "ERROR: unrecognised root device '${current_root}' in ${CMDLINE_FILE}"
        exit 1
        ;;
esac

log "switching slot ${current_slot} -> ${next_slot} (${current_root} -> ${next_root})"

# Backup current cmdline for rollback
cp "${CMDLINE_FILE}" "${CMDLINE_PREV}"

# Update cmdline.txt to boot from the new slot
sed "s|root=/dev/mmcblk0p[0-9]*|root=${next_root}|g" "${CMDLINE_PREV}" > "${CMDLINE_FILE}"

# Write boot state for rauc-boot-check.service and rauc-mark-good.service
cat > "${STATE_FILE}" <<EOF
pending_slot=${next_slot}
pending_root=${next_root}
prev_slot=${current_slot}
prev_root=${current_root}
boot_attempts=${BOOT_ATTEMPTS}
EOF

sync
log "done: next boot will use slot ${next_slot} (${next_root}), boot_attempts=${BOOT_ATTEMPTS}"
