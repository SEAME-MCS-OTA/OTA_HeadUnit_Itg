#!/bin/sh
# Ensure journald stores logs on shared /data so A/B rollback keeps boot history.
set -eu

SHARED_JOURNAL_DIR="/data/log/journal"
VOLATILE_LOG_DIR="/var/volatile/log"
JOURNAL_LINK="${VOLATILE_LOG_DIR}/journal"

mkdir -p "${SHARED_JOURNAL_DIR}"
mkdir -p "${VOLATILE_LOG_DIR}"

if [ -d "${JOURNAL_LINK}" ] && [ ! -L "${JOURNAL_LINK}" ]; then
    cp -a "${JOURNAL_LINK}/." "${SHARED_JOURNAL_DIR}/" 2>/dev/null || true
    rm -rf "${JOURNAL_LINK}"
fi

ln -sfn "${SHARED_JOURNAL_DIR}" "${JOURNAL_LINK}"
