#!/bin/sh
# RAUC custom bootloader backend for RPi A/B rootfs on mmcblk0p2/p3.
set -eu

BOOT_MOUNT="/boot"
CMDLINE_FILE="${BOOT_MOUNT}/cmdline.txt"
CMDLINE_PREV="${BOOT_MOUNT}/cmdline.prev.txt"
ROLLBACK_STATE_FILE="${BOOT_MOUNT}/rauc.state"
BACKEND_STATE_FILE="${BOOT_MOUNT}/rauc.bootstate"
BOOT_ATTEMPTS="${BOOT_ATTEMPTS:-3}"

slot_to_root() {
    case "${1}" in
        A) echo "/dev/mmcblk0p2" ;;
        B) echo "/dev/mmcblk0p3" ;;
        *) return 1 ;;
    esac
}

root_to_slot() {
    case "${1}" in
        /dev/mmcblk0p2) echo "A" ;;
        /dev/mmcblk0p3) echo "B" ;;
        *) return 1 ;;
    esac
}

mount_boot_rw() {
    if ! mountpoint -q "${BOOT_MOUNT}"; then
        mount "${BOOT_MOUNT}" >/dev/null 2>&1 || return 1
    fi
    mount -o remount,rw "${BOOT_MOUNT}" >/dev/null 2>&1 || true
    return 0
}

root_from_cmdline_file() {
    grep -o 'root=/dev/mmcblk0p[0-9]*' "${CMDLINE_FILE}" 2>/dev/null | sed 's/root=//' | head -n1
}

root_from_proc_cmdline() {
    grep -o 'root=/dev/mmcblk0p[0-9]*' /proc/cmdline 2>/dev/null | sed 's/root=//' | head -n1
}

slot_from_cmdline_file() {
    root="$(root_from_cmdline_file || true)"
    [ -n "${root}" ] || return 1
    root_to_slot "${root}"
}

slot_from_proc_cmdline() {
    root="$(root_from_proc_cmdline || true)"
    [ -n "${root}" ] || return 1
    root_to_slot "${root}"
}

load_backend_state() {
    PRIMARY=""
    STATE_A="good"
    STATE_B="good"

    if [ -f "${BACKEND_STATE_FILE}" ]; then
        # shellcheck disable=SC1090
        . "${BACKEND_STATE_FILE}"
    fi

    case "${STATE_A}" in
        good|bad) ;;
        *) STATE_A="good" ;;
    esac
    case "${STATE_B}" in
        good|bad) ;;
        *) STATE_B="good" ;;
    esac

    if [ -z "${PRIMARY}" ]; then
        PRIMARY="$(slot_from_cmdline_file || true)"
    fi
    if [ -z "${PRIMARY}" ]; then
        PRIMARY="A"
    fi
}

save_backend_state() {
    mount_boot_rw || return 1
    cat > "${BACKEND_STATE_FILE}" <<EOF
PRIMARY=${PRIMARY}
STATE_A=${STATE_A}
STATE_B=${STATE_B}
EOF
    sync
}

cmd_get_primary() {
    load_backend_state
    echo "${PRIMARY}"
}

cmd_get_current() {
    current="$(slot_from_proc_cmdline || slot_from_cmdline_file || true)"
    [ -n "${current}" ] || current="A"
    echo "${current}"
}

cmd_get_state() {
    slot="$(echo "${1:-}" | tr '[:lower:]' '[:upper:]')"
    load_backend_state
    case "${slot}" in
        A) echo "${STATE_A}" ;;
        B) echo "${STATE_B}" ;;
        *) return 1 ;;
    esac
}

cmd_set_state() {
    slot="$(echo "${1:-}" | tr '[:lower:]' '[:upper:]')"
    state="${2:-}"
    case "${state}" in
        good|bad) ;;
        *) return 1 ;;
    esac

    load_backend_state
    case "${slot}" in
        A) STATE_A="${state}" ;;
        B) STATE_B="${state}" ;;
        *) return 1 ;;
    esac
    save_backend_state
}

cmd_set_primary() {
    target_slot="$(echo "${1:-}" | tr '[:lower:]' '[:upper:]')"
    target_root="$(slot_to_root "${target_slot}")"

    mount_boot_rw || return 1

    current_slot="$(slot_from_cmdline_file || true)"
    current_root="$(root_from_cmdline_file || true)"
    if [ -z "${current_slot}" ]; then
        current_slot="${target_slot}"
    fi
    if [ -z "${current_root}" ]; then
        current_root="$(slot_to_root "${current_slot}" || true)"
    fi
    if [ -z "${current_root}" ]; then
        current_root="${target_root}"
    fi

    if [ "${current_root}" != "${target_root}" ]; then
        cp "${CMDLINE_FILE}" "${CMDLINE_PREV}"
        sed "s|root=/dev/mmcblk0p[0-9]*|root=${target_root}|g" "${CMDLINE_PREV}" > "${CMDLINE_FILE}"
    fi

    cat > "${ROLLBACK_STATE_FILE}" <<EOF
pending_slot=${target_slot}
pending_root=${target_root}
prev_slot=${current_slot}
prev_root=${current_root}
boot_attempts=${BOOT_ATTEMPTS}
EOF

    load_backend_state
    PRIMARY="${target_slot}"
    case "${target_slot}" in
        A) STATE_A="good" ;;
        B) STATE_B="good" ;;
    esac
    save_backend_state
    sync
}

cmd="${1:-}"
case "${cmd}" in
    get-primary)
        cmd_get_primary
        ;;
    set-primary)
        shift
        cmd_set_primary "$@"
        ;;
    get-state)
        shift
        cmd_get_state "$@"
        ;;
    set-state)
        shift
        cmd_set_state "$@"
        ;;
    get-current)
        cmd_get_current
        ;;
    *)
        exit 1
        ;;
esac
