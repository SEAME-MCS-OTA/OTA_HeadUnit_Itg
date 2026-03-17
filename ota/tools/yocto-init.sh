#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
YOCTO_WS="${YOCTO_WS:-${ROOT_DIR}/yocto-workspace}"
BUILD_DIR="${BUILD_DIR:-${YOCTO_WS}/build-des}"
META_RAUC_DIR="${YOCTO_WS}/meta-rauc"
YOCTO_BRANCH="${YOCTO_BRANCH:-scarthgap}"

if [[ ! -f "${YOCTO_WS}/poky/oe-init-build-env" ]]; then
  echo "ERROR: poky/oe-init-build-env not found: ${YOCTO_WS}/poky" >&2
  exit 1
fi

if [[ ! -d "${META_RAUC_DIR}/.git" && ! -f "${META_RAUC_DIR}/classes-recipe/bundle.bbclass" ]]; then
  echo "[info] meta-rauc not found. Cloning..."
  git clone --branch "${YOCTO_BRANCH}" --depth 1 https://github.com/rauc/meta-rauc.git "${META_RAUC_DIR}"
fi

if [[ ! -f "${BUILD_DIR}/conf/bblayers.conf" || ! -f "${BUILD_DIR}/conf/local.conf" ]]; then
  echo "[info] Initializing build dir: ${BUILD_DIR}"
  export BBSERVER="${BBSERVER:-}"
  set +u
  # shellcheck disable=SC1090
  source "${YOCTO_WS}/poky/oe-init-build-env" "${BUILD_DIR}" >/dev/null
  set -u
fi

BBLAYERS="${BUILD_DIR}/conf/bblayers.conf"
if [[ ! -f "${BBLAYERS}" ]]; then
  echo "ERROR: bblayers.conf not found: ${BBLAYERS}" >&2
  exit 1
fi

append_layer_if_missing() {
  local layer_path="$1"
  if ! grep -qF "${layer_path}" "${BBLAYERS}"; then
    echo "BBLAYERS += \" ${layer_path} \"" >> "${BBLAYERS}"
  fi
}

append_layer_if_missing '${TOPDIR}/../meta-rauc'
append_layer_if_missing '${TOPDIR}/../meta-openembedded/meta-oe'
append_layer_if_missing '${TOPDIR}/../meta-openembedded/meta-python'
append_layer_if_missing '${TOPDIR}/../meta-openembedded/meta-networking'
append_layer_if_missing '${TOPDIR}/../meta-qt6'
append_layer_if_missing '${TOPDIR}/../meta-raspberrypi'
append_layer_if_missing '${TOPDIR}/../meta-custom/meta-env'
append_layer_if_missing '${TOPDIR}/../meta-custom/meta-app'
append_layer_if_missing '${TOPDIR}/../meta-custom/meta-piracer'

echo "[ok] Yocto init complete"
echo "  YOCTO_WS: ${YOCTO_WS}"
echo "  BUILD_DIR: ${BUILD_DIR}"
echo "  meta-rauc: ${META_RAUC_DIR}"
