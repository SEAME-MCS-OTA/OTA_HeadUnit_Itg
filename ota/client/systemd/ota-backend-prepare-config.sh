#!/bin/sh
set -eu

DEFAULT_CFG="/etc/ota-backend/config.json"
PERSIST_DIR="/data/etc/ota-backend"
PERSIST_CFG="${PERSIST_DIR}/config.json"

mkdir -p "${PERSIST_DIR}"

if [ ! -s "${PERSIST_CFG}" ] && [ -s "${DEFAULT_CFG}" ]; then
  cp "${DEFAULT_CFG}" "${PERSIST_CFG}"
fi

if [ -s "${DEFAULT_CFG}" ] && [ -s "${PERSIST_CFG}" ]; then
  python3 - "${DEFAULT_CFG}" "${PERSIST_CFG}" <<'PY'
import json
import os
import sys
import tempfile
from urllib.parse import urlparse, urlunparse

default_path = sys.argv[1]
persist_path = sys.argv[2]

try:
    with open(default_path, "r", encoding="utf-8") as f:
        default_cfg = json.load(f)
except Exception:
    default_cfg = {}

try:
    with open(persist_path, "r", encoding="utf-8") as f:
        persist_cfg = json.load(f)
except Exception:
    persist_cfg = {}

def merge_missing(src, dst):
    for key, value in src.items():
        if key not in dst:
            dst[key] = value
        elif isinstance(value, dict) and isinstance(dst.get(key), dict):
            merge_missing(value, dst[key])
        elif (dst.get(key) is None or (isinstance(dst.get(key), str) and dst.get(key).strip() == "")) and value not in (None, ""):
            # Fill empty persisted scalar values from updated defaults.
            dst[key] = value


def parse_int(value):
    try:
        return int(value)
    except Exception:
        return None

if not isinstance(default_cfg, dict):
    default_cfg = {}
if not isinstance(persist_cfg, dict):
    persist_cfg = {}

merge_missing(default_cfg, persist_cfg)

# Config migration:
# Move legacy heartbeat values (30s+) to the new faster default (10s),
# while preserving explicit lower custom values.
default_hb = parse_int(default_cfg.get("mqtt_heartbeat_sec"))
if default_hb is None or default_hb <= 0:
    default_hb = 10
current_hb = parse_int(persist_cfg.get("mqtt_heartbeat_sec"))
if current_hb is None or current_hb >= 30:
    persist_cfg["mqtt_heartbeat_sec"] = default_hb

# Config migration:
# Ensure collector_url explicitly points to /ingest.
collector_url = str(persist_cfg.get("collector_url") or "").strip()
if collector_url:
    try:
        parsed = urlparse(collector_url)
        path = parsed.path or ""
        if path in ("", "/"):
            parsed = parsed._replace(path="/ingest")
            persist_cfg["collector_url"] = urlunparse(parsed)
    except Exception:
        pass

tmp_fd, tmp_path = tempfile.mkstemp(prefix="ota-config-", suffix=".json", dir=os.path.dirname(persist_path))
with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
    json.dump(persist_cfg, f, ensure_ascii=False, indent=2)
os.replace(tmp_path, persist_path)
PY
fi
