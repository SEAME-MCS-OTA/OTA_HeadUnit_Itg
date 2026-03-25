#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
YOCTO_WS="${YOCTO_WS:-${ROOT_DIR}/yocto-workspace}"
BUILD_DIR="${BUILD_DIR:-${YOCTO_WS}/build-des}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${ROOT_DIR}/out}"
BUNDLE_RECIPE="${BUNDLE_RECIPE:-des-hu-bundle}"
MACHINE="${MACHINE:-raspberrypi4-64}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
RAUC_KEY_FILE="${RAUC_KEY_FILE:-${ROOT_DIR}/ota/keys/rauc/rauc.key.pem}"
RAUC_CERT_FILE="${RAUC_CERT_FILE:-${ROOT_DIR}/ota/keys/rauc/rauc.cert.pem}"
DEPLOY_DIR="${BUILD_DIR}/tmp-glibc/deploy/images/${MACHINE}"
BUNDLE_LINK_PATH="${DEPLOY_DIR}/${BUNDLE_RECIPE}-${MACHINE}.raucb"
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

if [[ "${FORCE_REBUILD}" == "1" ]]; then
  echo "[info] FORCE_REBUILD=1 -> cleansstate: headunit ota-backend des-image ${BUNDLE_RECIPE}"
  bitbake -c cleansstate headunit ota-backend des-image "${BUNDLE_RECIPE}"
fi

bitbake "${BUNDLE_RECIPE}"

if [[ ! -d "${DEPLOY_DIR}" ]]; then
  echo "ERROR: deploy dir not found: ${DEPLOY_DIR}" >&2
  exit 1
fi

if ! compgen -G "${DEPLOY_DIR}/*.raucb" >/dev/null; then
  echo "ERROR: no .raucb artifact found in ${DEPLOY_DIR}" >&2
  exit 1
fi

resolve_bundle_artifact() {
  if [[ -L "${BUNDLE_LINK_PATH}" ]]; then
    readlink -f "${BUNDLE_LINK_PATH}"
    return
  fi
  if [[ -f "${BUNDLE_LINK_PATH}" ]]; then
    printf '%s\n' "${BUNDLE_LINK_PATH}"
    return
  fi
  ls -1t "${DEPLOY_DIR}/${BUNDLE_RECIPE}-${MACHINE}-"*.raucb 2>/dev/null | head -n1
}

BUNDLE_REAL_PATH="$(resolve_bundle_artifact || true)"
if [[ -z "${BUNDLE_REAL_PATH}" || ! -f "${BUNDLE_REAL_PATH}" ]]; then
  echo "ERROR: could not resolve bundle artifact from ${DEPLOY_DIR}" >&2
  exit 1
fi

BUNDLE_REAL_NAME="$(basename "${BUNDLE_REAL_PATH}")"
cp -v "${BUNDLE_REAL_PATH}" "${ARTIFACTS_DIR}/${BUNDLE_REAL_NAME}"
ln -sfn "${BUNDLE_REAL_NAME}" "${ARTIFACTS_DIR}/${BUNDLE_RECIPE}-${MACHINE}.raucb"

if command -v sha256sum >/dev/null 2>&1; then
  BUNDLE_SHA256="$(sha256sum "${ARTIFACTS_DIR}/${BUNDLE_REAL_NAME}" | awk '{print $1}')"
  echo "[ok] bundle copied: ${ARTIFACTS_DIR}/${BUNDLE_REAL_NAME} (sha256=${BUNDLE_SHA256})"
else
  echo "[ok] bundle copied: ${ARTIFACTS_DIR}/${BUNDLE_REAL_NAME}"
fi
