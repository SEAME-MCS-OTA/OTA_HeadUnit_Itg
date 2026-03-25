#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
YOCTO_WS="${YOCTO_WS:-${ROOT_DIR}/yocto-workspace}"
BUILD_DIR="${BUILD_DIR:-${YOCTO_WS}/build-des}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${ROOT_DIR}/out}"
IMAGE_RECIPE="${IMAGE_RECIPE:-des-image}"
MACHINE="${MACHINE:-raspberrypi4-64}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"

mkdir -p "${ARTIFACTS_DIR}"

export BBSERVER="${BBSERVER:-}"
set +u
# shellcheck disable=SC1090
source "${YOCTO_WS}/poky/oe-init-build-env" "${BUILD_DIR}" >/dev/null
set -u

if [[ "${FORCE_REBUILD}" == "1" ]]; then
  echo "[info] FORCE_REBUILD=1 -> cleansstate: headunit ota-backend ${IMAGE_RECIPE}"
  bitbake -c cleansstate headunit ota-backend "${IMAGE_RECIPE}"
fi

bitbake "${IMAGE_RECIPE}"

DEPLOY_DIR="${BUILD_DIR}/tmp-glibc/deploy/images/${MACHINE}"
if [[ ! -d "${DEPLOY_DIR}" ]]; then
  echo "ERROR: deploy dir not found: ${DEPLOY_DIR}" >&2
  exit 1
fi

copy_linked_artifact() {
  local link_path="$1"
  local label="$2"
  local resolved=""
  local out_link=""

  if [[ -L "${link_path}" ]]; then
    resolved="$(readlink -f "${link_path}")"
    out_link="${ARTIFACTS_DIR}/$(basename "${link_path}")"
  elif [[ -f "${link_path}" ]]; then
    resolved="${link_path}"
  else
    echo "[warn] missing ${label}: ${link_path}"
    return 0
  fi

  if [[ -z "${resolved}" || ! -f "${resolved}" ]]; then
    echo "[warn] invalid ${label} target: ${link_path}"
    return 0
  fi

  local real_name
  real_name="$(basename "${resolved}")"
  cp -v "${resolved}" "${ARTIFACTS_DIR}/${real_name}"

  if [[ -n "${out_link}" ]]; then
    ln -sfn "${real_name}" "${out_link}"
  fi
}

copy_linked_artifact "${DEPLOY_DIR}/${IMAGE_RECIPE}-${MACHINE}.rootfs.wic.bz2" "wic.bz2"
copy_linked_artifact "${DEPLOY_DIR}/${IMAGE_RECIPE}-${MACHINE}.rootfs.ext4.bz2" "ext4.bz2"
copy_linked_artifact "${DEPLOY_DIR}/${IMAGE_RECIPE}-${MACHINE}.rootfs.wic.bmap" "wic.bmap"

echo "[ok] image artifacts copied to ${ARTIFACTS_DIR}"
