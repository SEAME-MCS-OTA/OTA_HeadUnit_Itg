#!/usr/bin/env bash

# This script must be executed, not sourced.
# Sourcing would leak shell options (set -euo pipefail) into the current shell.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo "[error] Do not source this script."
  echo "        Run: ./ota/tools/ota-stack-down.sh"
  return 1 2>/dev/null || exit 1
fi

set -euo pipefail

# Script location: <repo>/ota/tools
# Use repository root for compose path.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.ota-stack.yml"

cd "${ROOT_DIR}"
# Keep profile set aligned with stack-up defaults so profile services
# (e.g., local MQTT broker) are also included on down.
export COMPOSE_PROFILES="${COMPOSE_PROFILES:-local-broker}"
docker compose -f "${COMPOSE_FILE}" down
