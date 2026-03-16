#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

"${ROOT_DIR}/ota/tools/rauc-generate-keys.sh" "${ROOT_DIR}/ota/keys/rauc"
"${ROOT_DIR}/ota/tools/ed25519-generate-keys.sh" "${ROOT_DIR}/ota/keys/ed25519"

echo "[ok] OTA key generation complete"
echo "  RAUC:    ${ROOT_DIR}/ota/keys/rauc"
echo "  ED25519: ${ROOT_DIR}/ota/keys/ed25519"
