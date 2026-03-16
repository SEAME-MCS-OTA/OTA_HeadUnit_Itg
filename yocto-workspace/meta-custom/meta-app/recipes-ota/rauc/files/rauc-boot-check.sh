#!/bin/sh
# RAUC boot check: manages A/B bootcount and triggers rollback when needed.
# Runs early in boot (After=local-fs.target, Before=sysinit.target).
set -e

BOOT_MOUNT="/boot"
STATE_FILE="${BOOT_MOUNT}/rauc.state"
CMDLINE_FILE="${BOOT_MOUNT}/cmdline.txt"
CMDLINE_PREV="${BOOT_MOUNT}/cmdline.prev.txt"
LOG_TAG="rauc-boot-check"

log() { echo "${LOG_TAG}: $*"; logger -t "${LOG_TAG}" "$*" 2>/dev/null || true; }

[ -f "${STATE_FILE}" ] || { log "no pending update, nothing to do"; exit 0; }

# Read state variables
# shellcheck disable=SC1090
. "${STATE_FILE}"

# Get actual booted root device from kernel cmdline
actual_root=$(grep -o 'root=/dev/mmcblk0p[0-9]*' /proc/cmdline | sed 's/root=//' | head -n1)

log "state: pending_slot=${pending_slot} pending_root=${pending_root} boot_attempts=${boot_attempts}"
log "actual root: ${actual_root}"

# Ensure /boot is writable
mount -o remount,rw "${BOOT_MOUNT}" 2>/dev/null || true

if [ "${actual_root}" != "${pending_root}" ]; then
    # We're not on the pending slot – state is stale, clean up
    log "not on pending slot (expected ${pending_root}, got ${actual_root}), clearing state"
    rm -f "${STATE_FILE}"
    exit 0
fi

# We are on the pending slot – decrement boot_attempts
new_attempts=$((boot_attempts - 1))
log "boot_attempts: ${boot_attempts} -> ${new_attempts}"

if [ "${new_attempts}" -le 0 ]; then
    # All attempts exhausted without mark-good → rollback
    log "ROLLBACK: all boot attempts exhausted, reverting to slot ${prev_slot} (${prev_root})"
    if [ -f "${CMDLINE_PREV}" ]; then
        cp "${CMDLINE_PREV}" "${CMDLINE_FILE}"
        rm -f "${CMDLINE_PREV}"
    else
        # No backup – reconstruct cmdline pointing to prev_root
        sed "s|root=/dev/mmcblk0p[0-9]*|root=${prev_root}|g" "${CMDLINE_FILE}" > "${CMDLINE_FILE}.tmp"
        mv "${CMDLINE_FILE}.tmp" "${CMDLINE_FILE}"
    fi
    rm -f "${STATE_FILE}"
    sync
    log "rollback complete, rebooting"
    reboot -f
else
    # Still have attempts left – update counter and continue booting
    sed -i "s/^boot_attempts=.*/boot_attempts=${new_attempts}/" "${STATE_FILE}"
    sync
    log "continuing boot on slot ${pending_slot}, ${new_attempts} attempt(s) remaining"
fi
