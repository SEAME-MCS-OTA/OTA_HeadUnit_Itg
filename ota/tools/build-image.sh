#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
YOCTO_WS="${YOCTO_WS:-${ROOT_DIR}/yocto-workspace}"
BUILD_DIR="${BUILD_DIR:-${YOCTO_WS}/build-des}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${ROOT_DIR}/out}"
IMAGE_RECIPE="${IMAGE_RECIPE:-des-image}"
MACHINE="${MACHINE:-raspberrypi4-64}"

mkdir -p "${ARTIFACTS_DIR}"

export BBSERVER="${BBSERVER:-}"
set +u
# shellcheck disable=SC1090
source "${YOCTO_WS}/poky/oe-init-build-env" "${BUILD_DIR}" >/dev/null
set -u

bitbake "${IMAGE_RECIPE}"

DEPLOY_DIR="${BUILD_DIR}/tmp-glibc/deploy/images/${MACHINE}"
if [[ ! -d "${DEPLOY_DIR}" ]]; then
  echo "ERROR: deploy dir not found: ${DEPLOY_DIR}" >&2
  exit 1
fi

cp -v "${DEPLOY_DIR}/${IMAGE_RECIPE}-${MACHINE}.rootfs.wic.bz2"* "${ARTIFACTS_DIR}/" 2>/dev/null || true
cp -v "${DEPLOY_DIR}/${IMAGE_RECIPE}-${MACHINE}.rootfs.ext4.bz2"* "${ARTIFACTS_DIR}/" 2>/dev/null || true
cp -v "${DEPLOY_DIR}/${IMAGE_RECIPE}-${MACHINE}.rootfs.wic.bmap"* "${ARTIFACTS_DIR}/" 2>/dev/null || true

echo "[ok] image artifacts copied to ${ARTIFACTS_DIR}"
