#!/bin/sh
# RAUC health guard:
# - On pending OTA slot, wait until weston/headunit are stable.
# - If stable: mark slot good and clear pending state.
# - If headunit keeps failing (e.g. QML load error) or timeout: rollback and reboot.
set -eu

BOOT_MOUNT="/boot"
STATE_FILE="${BOOT_MOUNT}/rauc.state"
CMDLINE_FILE="${BOOT_MOUNT}/cmdline.txt"
CMDLINE_PREV="${BOOT_MOUNT}/cmdline.prev.txt"
LOG_TAG="rauc-mark-good"

HEALTH_TIMEOUT_SEC="${RAUC_HEALTH_TIMEOUT_SEC:-90}"
STABLE_REQUIRED_SEC="${RAUC_STABLE_REQUIRED_SEC:-12}"
MAX_HEADUNIT_RESTARTS="${RAUC_MAX_HEADUNIT_RESTARTS:-6}"
POLL_SEC=2

log() { echo "${LOG_TAG}: $*"; logger -t "${LOG_TAG}" "$*" 2>/dev/null || true; }

read_restarts() {
    v="$(systemctl show headunit.service -p NRestarts --value 2>/dev/null || echo 0)"
    case "${v}" in
        ''|*[!0-9]*) echo 0 ;;
        *) echo "${v}" ;;
    esac
}

rollback_and_reboot() {
    reason="$1"
    log "ROLLBACK: ${reason}"

    mount -o remount,rw "${BOOT_MOUNT}" 2>/dev/null || true

    if [ -f "${CMDLINE_PREV}" ]; then
        cp "${CMDLINE_PREV}" "${CMDLINE_FILE}"
        rm -f "${CMDLINE_PREV}"
    elif [ -n "${prev_root:-}" ] && [ -f "${CMDLINE_FILE}" ]; then
        sed "s|root=/dev/mmcblk0p[0-9]*|root=${prev_root}|g" "${CMDLINE_FILE}" > "${CMDLINE_FILE}.tmp"
        mv "${CMDLINE_FILE}.tmp" "${CMDLINE_FILE}"
    else
        log "WARN: cannot restore cmdline (no backup and no prev_root)"
    fi

    rm -f "${STATE_FILE}"
    sync

    log "rollback prepared, rebooting now"
    systemctl --no-block reboot >/dev/null 2>&1 || reboot -f
    sleep 2
    reboot -f
}

[ -f "${STATE_FILE}" ] || { log "no pending state, nothing to do"; exit 0; }

# shellcheck disable=SC1090
. "${STATE_FILE}"

actual_root="$(grep -o 'root=/dev/mmcblk0p[0-9]*' /proc/cmdline | sed 's/root=//' | head -n1)"
log "pending_slot=${pending_slot:-?} pending_root=${pending_root:-?} prev_root=${prev_root:-?} actual_root=${actual_root}"

mount -o remount,rw "${BOOT_MOUNT}" 2>/dev/null || true

if [ "${actual_root}" != "${pending_root:-}" ]; then
    log "not on pending slot; clearing stale state"
    rm -f "${STATE_FILE}" "${CMDLINE_PREV}"
    sync
    exit 0
fi

start_ts="$(date +%s)"
stable_for=0
restart_base="$(read_restarts)"
log "health-check start: timeout=${HEALTH_TIMEOUT_SEC}s stable_required=${STABLE_REQUIRED_SEC}s restart_base=${restart_base}"

while :; do
    now_ts="$(date +%s)"
    elapsed="$((now_ts - start_ts))"

    weston_ok=0
    headunit_ok=0
    systemctl is-active --quiet weston.service && weston_ok=1 || true
    systemctl is-active --quiet headunit.service && headunit_ok=1 || true

    restarts_now="$(read_restarts)"
    restart_delta="$((restarts_now - restart_base))"

    if [ "${restart_delta}" -ge "${MAX_HEADUNIT_RESTARTS}" ]; then
        rollback_and_reboot "headunit restart loop detected (delta=${restart_delta})"
    fi

    if [ "${weston_ok}" -eq 1 ] && [ "${headunit_ok}" -eq 1 ]; then
        stable_for="$((stable_for + POLL_SEC))"
        if [ "${stable_for}" -ge "${STABLE_REQUIRED_SEC}" ]; then
            log "UI stable for ${stable_for}s on pending slot; marking good"
            rauc status mark-good && log "rauc mark-good: OK" || log "rauc mark-good: failed (ignored)"
            rm -f "${STATE_FILE}" "${CMDLINE_PREV}"
            sync
            log "slot confirmed good; pending state cleared"
            exit 0
        fi
    else
        stable_for=0
        if systemctl is-failed --quiet headunit.service; then
            rollback_and_reboot "headunit entered failed state"
        fi
    fi

    if [ "${elapsed}" -ge "${HEALTH_TIMEOUT_SEC}" ]; then
        rollback_and_reboot "health-check timeout (${HEALTH_TIMEOUT_SEC}s) without stable UI"
    fi

    sleep "${POLL_SEC}"
done
