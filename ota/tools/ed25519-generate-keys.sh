#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-${ROOT_DIR}/ota/keys/ed25519}"

mkdir -p "${OUT_DIR}"

openssl genpkey -algorithm ED25519 -out "${OUT_DIR}/ota-signing.key"
openssl pkey -in "${OUT_DIR}/ota-signing.key" -pubout -out "${OUT_DIR}/ota-signing.pub"

chmod 600 "${OUT_DIR}/ota-signing.key"
chmod 644 "${OUT_DIR}/ota-signing.pub"

printf "Generated:\n- %s\n- %s\n" \
  "${OUT_DIR}/ota-signing.key" \
  "${OUT_DIR}/ota-signing.pub"
