#!/usr/bin/env bash

# This script must be executed, not sourced.
# Sourcing would leak shell options (set -euo pipefail) into the current shell.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo "[error] Do not source this script."
  echo "        Run: ./ota/tools/ota-stack-up.sh"
  return 1 2>/dev/null || exit 1
fi

set -euo pipefail

# Script location: <repo>/ota/tools
# Use repository root for compose/.env paths.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.ota-stack.yml"
LEGACY_OTA_GH_COMPOSE="${ROOT_DIR}/ota/server/docker-compose.yml"
ENV_FILE="${ROOT_DIR}/.env"

cd "${ROOT_DIR}"

# Disable compose Bake path by default to avoid buildx warnings on hosts
# where docker-buildx-plugin is not installed.
export COMPOSE_BAKE="${COMPOSE_BAKE:-false}"
# Enable local MQTT broker profile only when server is configured
# to use the compose-local broker alias.
if [[ "${OTA_GH_MQTT_BROKER_HOST:-}" == "ota_gh_mosquitto" ]]; then
  export COMPOSE_PROFILES="${COMPOSE_PROFILES:-local-broker}"
fi

detect_host_ip() {
  local ip=""
  if command -v ip >/dev/null 2>&1; then
    ip="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
  fi
  if [[ -z "${ip}" ]] && command -v hostname >/dev/null 2>&1; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  echo "${ip}"
}

upsert_env_var() {
  local key="$1"
  local value="$2"
  local file="$3"
  touch "${file}"
  if grep -qE "^${key}=" "${file}"; then
    sed -i "s#^${key}=.*#${key}=${value}#g" "${file}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${file}"
  fi
}

# RPi must download firmware from a host-reachable URL.
# If not provided, auto-derive a sane default from current host IP.
if [[ -z "${OTA_GH_FIRMWARE_BASE_URL:-}" ]]; then
  HOST_IP="$(detect_host_ip)"
  if [[ -n "${HOST_IP}" ]]; then
    export OTA_GH_FIRMWARE_BASE_URL="http://${HOST_IP}:${OTA_GH_SERVER_PORT:-8080}"
    echo "[info] OTA_GH_FIRMWARE_BASE_URL not set. Using ${OTA_GH_FIRMWARE_BASE_URL}"
    upsert_env_var "OTA_GH_FIRMWARE_BASE_URL" "${OTA_GH_FIRMWARE_BASE_URL}" "${ENV_FILE}"
  else
    echo "[warn] Could not detect host IP. OTA firmware URL may fall back to localhost."
  fi
fi

# If legacy OTA_GH stack is running, it usually occupies 8080/1883 and
# prevents this unified stack from starting. Stop it automatically.
if [[ "${OTA_STACK_SKIP_LEGACY_DOWN:-0}" != "1" ]] && [[ -f "${LEGACY_OTA_GH_COMPOSE}" ]]; then
  if docker compose -f "${LEGACY_OTA_GH_COMPOSE}" ps -q | grep -q .; then
    echo "[info] Stopping legacy OTA_GH stack to avoid port conflicts..."
    docker compose -f "${LEGACY_OTA_GH_COMPOSE}" down
  fi
fi

docker compose -f "${COMPOSE_FILE}" up -d --build

echo
echo "== OTA stack services =="
docker compose -f "${COMPOSE_FILE}" ps
echo
echo "OTA_GH API:        http://localhost:${OTA_GH_SERVER_PORT:-8080}"
echo "OTA_GH Dashboard:  http://localhost:${OTA_GH_DASHBOARD_PORT:-3001}"
echo "OTA_VLM Backend:   http://localhost:${OTA_VLM_BACKEND_PORT:-4000}"
echo "OTA_VLM Frontend:  http://localhost:${OTA_VLM_FRONTEND_PORT:-5173}"
