#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
YOCTO_WS="${YOCTO_WS:-${ROOT_DIR}/yocto-workspace}"
BUILD_DIR="${BUILD_DIR:-${YOCTO_WS}/build-des}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${ROOT_DIR}/out}"
BUNDLE_RECIPE="${BUNDLE_RECIPE:-des-hu-bundle}"
MACHINE="${MACHINE:-raspberrypi4-64}"
RAUC_KEY_FILE="${RAUC_KEY_FILE:-${ROOT_DIR}/ota/keys/rauc/rauc.key.pem}"
RAUC_CERT_FILE="${RAUC_CERT_FILE:-${ROOT_DIR}/ota/keys/rauc/rauc.cert.pem}"
DEPLOY_DIR="${BUILD_DIR}/tmp-glibc/deploy/images/${MACHINE}"
IMAGE_LINK_BASENAME="${IMAGE_RECIPE:-des-image}-${MACHINE}"
EXT4_LINK_PATH="${DEPLOY_DIR}/${IMAGE_LINK_BASENAME}.rootfs.ext4"

mkdir -p "${ARTIFACTS_DIR}"

if [[ ! -f "${RAUC_KEY_FILE}" || ! -f "${RAUC_CERT_FILE}" ]]; then
  echo "ERROR: RAUC signing key/cert not found." >&2
  echo "  expected key : ${RAUC_KEY_FILE}" >&2
  echo "  expected cert: ${RAUC_CERT_FILE}" >&2
  echo "Run: ./ota/tools/ota-generate-keys.sh" >&2
  exit 1
fi

# BitBake deploy dir is manifest-protected.
# If a manual plain file exists at the link path (e.g. hand-decompressed ext4),
# it causes do_image_complete conflict: "(not matched to any task)".
if [[ -e "${EXT4_LINK_PATH}" && ! -L "${EXT4_LINK_PATH}" ]]; then
  echo "[warn] Removing unmanaged deploy file: ${EXT4_LINK_PATH}"
  rm -f "${EXT4_LINK_PATH}"
fi

export BBSERVER="${BBSERVER:-}"
set +u
# shellcheck disable=SC1090
source "${YOCTO_WS}/poky/oe-init-build-env" "${BUILD_DIR}" >/dev/null
set -u

bitbake "${BUNDLE_RECIPE}"

if [[ ! -d "${DEPLOY_DIR}" ]]; then
  echo "ERROR: deploy dir not found: ${DEPLOY_DIR}" >&2
  exit 1
fi

if ! compgen -G "${DEPLOY_DIR}/*.raucb" >/dev/null; then
  echo "ERROR: no .raucb artifact found in ${DEPLOY_DIR}" >&2
  exit 1
fi

cp -v "${DEPLOY_DIR}"/*.raucb "${ARTIFACTS_DIR}/"

echo "[ok] bundle artifacts copied to ${ARTIFACTS_DIR}"
