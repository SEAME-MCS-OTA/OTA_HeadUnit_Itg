import re
from datetime import datetime
from typing import Any, Dict, Optional


def _new_ota_id(prefix: str = "mqtt") -> str:
    safe_prefix = re.sub(r"[^a-zA-Z0-9_-]", "-", (prefix or "mqtt")).strip("-")
    if not safe_prefix:
        safe_prefix = "mqtt"
    return f"{safe_prefix}-{datetime.now().strftime('%Y%m%d-%H%M%S')}"


def parse_mqtt_update_command(
    payload: Dict[str, Any],
    default_ota_id_prefix: str = "mqtt",
) -> Optional[Dict[str, Any]]:
    """
    Normalize MQTT command payload to ota_id/url/target_version.

    Supported payloads:
    1) {"command":"update","firmware":{"url":"...","version":"1.2.3"}}
    2) {"ota_id":"...","url":"...","target_version":"1.2.3"}
    """
    if not isinstance(payload, dict):
        return None

    command = payload.get("command")
    if command is not None and str(command).strip().lower() != "update":
        return None

    firmware = payload.get("firmware")
    if isinstance(firmware, dict):
        url = str(firmware.get("url", payload.get("url", ""))).strip()
        target_version = str(
            firmware.get("version")
            or payload.get("target_version")
            or payload.get("version")
            or ""
        ).strip()
        expected_sha256 = str(
            firmware.get("sha256")
            or firmware.get("expected_sha256")
            or payload.get("expected_sha256")
            or payload.get("sha256")
            or ""
        ).strip().lower()
        expected_size = firmware.get("size", payload.get("expected_size"))
        signature = firmware.get("signature", payload.get("signature"))
    else:
        url = str(payload.get("url", "")).strip()
        target_version = str(payload.get("target_version") or payload.get("version") or "").strip()
        expected_sha256 = str(payload.get("expected_sha256") or payload.get("sha256") or "").strip().lower()
        expected_size = payload.get("expected_size")
        signature = payload.get("signature")

    if not url or not target_version:
        return None

    ota_id = str(payload.get("ota_id", "")).strip() or _new_ota_id(default_ota_id_prefix)
    out: Dict[str, Any] = {
        "ota_id": ota_id,
        "url": url,
        "target_version": target_version,
    }
    if expected_sha256:
        out["expected_sha256"] = expected_sha256
    try:
        if expected_size is not None and str(expected_size).strip() != "":
            out["expected_size"] = int(expected_size)
    except Exception:
        pass
    if isinstance(signature, dict):
        out["signature"] = signature
    return out
