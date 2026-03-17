#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-${ROOT_DIR}/ota/keys/rauc}"
RECIPE_CA_PATH="${ROOT_DIR}/yocto-workspace/meta-custom/meta-app/recipes-ota/rauc/files/ca.cert.pem"
mkdir -p "${OUT_DIR}"

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "${OUT_DIR}/rauc.key.pem"
openssl req -x509 -new -nodes -key "${OUT_DIR}/rauc.key.pem" -sha256 -days 3650 \
  -subj "/C=DE/O=IVI Head Unit/OU=OTA/CN=ivi-rauc" \
  -out "${OUT_DIR}/rauc.cert.pem"

chmod 600 "${OUT_DIR}/rauc.key.pem"
cp -f "${OUT_DIR}/rauc.cert.pem" "${RECIPE_CA_PATH}"

printf "Generated:\n- %s\n- %s\nSynced keyring cert:\n- %s\n" \
  "${OUT_DIR}/rauc.key.pem" "${OUT_DIR}/rauc.cert.pem" "${RECIPE_CA_PATH}"
