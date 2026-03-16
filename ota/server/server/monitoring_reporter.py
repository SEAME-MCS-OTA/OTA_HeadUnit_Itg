"""
OTA 결과를 OTA_VLM 관제 ingest API로 전송하는 유틸리티.
"""
import logging
from datetime import datetime, timezone
from typing import Optional, Any, Dict
from uuid import uuid4

import requests

from config import Config

logger = logging.getLogger(__name__)

_FINAL_STATUSES = {"completed", "failed"}


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _time_bucket(dt: datetime) -> str:
    hour = dt.hour
    if 6 <= hour < 12:
        return "MORNING"
    if 12 <= hour < 18:
        return "DAY"
    if 18 <= hour < 22:
        return "EVENING"
    return "NIGHT"


def should_report_final_status(status: str, previous_status: Optional[str]) -> bool:
    """최종 상태(completed/failed) 전환 시점에만 관제로 전송."""
    now_status = str(status or "").strip().lower()
    prev = str(previous_status or "").strip().lower()
    return now_status in _FINAL_STATUSES and now_status != prev


def _pick(obj: Dict[str, Any], dotted_path: str, default: Any = None) -> Any:
    cur: Any = obj
    try:
        for key in dotted_path.split("."):
            if not isinstance(cur, dict) or key not in cur:
                return default
            cur = cur[key]
        return cur
    except Exception:
        return default


def publish_update_result(
    *,
    vehicle_id: str,
    target_version: str,
    status: str,
    message: str = "",
    current_version: Optional[str] = None,
    from_version: Optional[str] = None,
    progress: Optional[int] = None,
    source: str = "ota-gh",
    status_payload: Optional[Dict[str, Any]] = None,
) -> bool:
    """
    OTA 완료/실패 결과를 OTA_VLM 백엔드(/ingest)로 전송.
    실패해도 OTA 플로우를 깨지 않도록 예외를 삼키고 False 반환.
    """
    url = Config.MONITORING_INGEST_URL
    if not url:
        logger.debug("Monitoring ingest skipped: MONITORING_INGEST_URL is empty")
        return False

    status_norm = str(status or "").strip().lower()
    event = "OK" if status_norm == "completed" else "FAIL"
    error_code = "NONE" if status_norm == "completed" else "OTA_FAILED"
    now_utc = datetime.now(timezone.utc)
    local_time = now_utc.astimezone().replace(microsecond=0)
    ota_id = f"ota-{now_utc.strftime('%Y%m%d%H%M%S')}-{uuid4().hex[:8]}"

    payload = {
        "ts": _utc_now_iso(),
        "device": {
            "device_id": vehicle_id,
            "model": Config.MONITORING_DEVICE_MODEL,
            "hw_rev": "1.2",
            "serial": "",
            "current_slot": "-",
        },
        "log_vehicle": {
            "brand": Config.MONITORING_VEHICLE_BRAND,
            "series": Config.MONITORING_VEHICLE_SERIES,
            "segment": Config.MONITORING_VEHICLE_SEGMENT,
            "fuel": Config.MONITORING_VEHICLE_FUEL,
        },
        "ota": {
            "ota_id": ota_id,
            "type": Config.MONITORING_OTA_TYPE,
            "current_version": str(from_version or current_version or ""),
            "target_version": str(target_version or ""),
            "phase": "REPORT",
            "event": event,
            "attempt": 1,
            "progress": int(progress) if progress is not None else (100 if status_norm == "completed" else 0),
        },
        "context": {
            "region": {
                "country": Config.MONITORING_REGION_COUNTRY,
                "city": Config.MONITORING_REGION_CITY,
                "timezone": Config.MONITORING_REGION_TIMEZONE,
            },
            "time": {
                "local": local_time.isoformat(),
                "day_of_week": local_time.strftime("%a"),
                "time_bucket": _time_bucket(local_time),
            },
            "power": {
                "source": "UNKNOWN",
                "battery_pct": 0,
                "battery": {
                    "pct": 0,
                    "state": "UNKNOWN",
                    "voltage_mv": 0,
                },
            },
            "environment": {
                "temp_c": 0,
                "cpu_load_pct": 0,
                "mem_free_mb": 0,
                "storage_free_mb": 0,
            },
            "network": {
                "iface": "wlan0",
                "ip": "",
                "latency_ms": 0,
                "rssi_dbm": 0,
                "gateway_reachable": True,
            },
            "vehicle_state": {
                "driving": False,
                "speed_kph": 0,
            },
        },
        "error": {
            "code": error_code,
            "message": str(message or ""),
            "retryable": status_norm == "failed",
        },
        "evidence": {
            "ota_log": [],
            "journal_log": [],
            "filesystem": [],
            "boot_state": {
                "bootcount": 0,
                "upgrade_available": False,
            },
        },
        "user_interaction": {
            "user_action": "NONE",
            "power_event": "NONE",
        },
        "artifacts": {
            "screenshot_path": "",
            "log_bundle_path": "",
        },
        "report": {
            "sent": False,
            "sent_at": "",
            "server_response": "",
        },
        "meta": {
            "source": source,
        },
    }

    # If caller provides richer status payload (e.g., device MQTT status),
    # merge network/time/error evidence to avoid all-zero summary records.
    raw = status_payload if isinstance(status_payload, dict) else {}
    raw_ota_id = str(_pick(raw, "ota.ota_id", _pick(raw, "ota_id", "")) or "").strip()
    if raw_ota_id:
        payload["ota"]["ota_id"] = raw_ota_id
    raw_phase = str(_pick(raw, "ota.phase", "")) or ""
    if raw_phase:
        payload["ota"]["phase"] = raw_phase
    raw_event = str(_pick(raw, "ota.event", "")) or ""
    if raw_event:
        payload["ota"]["event"] = raw_event
    raw_current = str(_pick(raw, "ota.current_version", "")) or ""
    if raw_current:
        payload["ota"]["current_version"] = raw_current
    raw_target = str(_pick(raw, "ota.target_version", "")) or ""
    if raw_target:
        payload["ota"]["target_version"] = raw_target
    raw_slot = str(_pick(raw, "device.current_slot", "")) or ""
    if raw_slot:
        payload["device"]["current_slot"] = raw_slot

    raw_network = _pick(raw, "context.network", {})
    if isinstance(raw_network, dict):
        if str(raw_network.get("iface", "")).strip():
            payload["context"]["network"]["iface"] = str(raw_network.get("iface"))
        if str(raw_network.get("ip", "")).strip():
            payload["context"]["network"]["ip"] = str(raw_network.get("ip"))
        try:
            payload["context"]["network"]["rssi_dbm"] = int(raw_network.get("rssi_dbm"))
        except Exception:
            pass
        try:
            payload["context"]["network"]["latency_ms"] = int(raw_network.get("latency_ms"))
        except Exception:
            pass
        if "gateway_reachable" in raw_network:
            payload["context"]["network"]["gateway_reachable"] = bool(raw_network.get("gateway_reachable"))

    raw_time = _pick(raw, "context.time", {})
    if isinstance(raw_time, dict) and str(raw_time.get("local", "")).strip():
        payload["context"]["time"]["local"] = str(raw_time.get("local"))
        payload["context"]["time"]["day_of_week"] = str(raw_time.get("day_of_week") or payload["context"]["time"]["day_of_week"])
        payload["context"]["time"]["time_bucket"] = str(raw_time.get("time_bucket") or payload["context"]["time"]["time_bucket"])

    raw_error = _pick(raw, "error", {})
    if isinstance(raw_error, dict):
        code = str(raw_error.get("code", "")).strip()
        msg = str(raw_error.get("message", "")).strip()
        if code:
            payload["error"]["code"] = code
        if msg:
            payload["error"]["message"] = msg
        if "retryable" in raw_error:
            payload["error"]["retryable"] = bool(raw_error.get("retryable"))

    for key in ("ota_log", "journal_log", "filesystem"):
        arr = _pick(raw, f"evidence.{key}", None)
        if isinstance(arr, list) and arr:
            payload["evidence"][key] = arr

    try:
        resp = requests.post(
            url,
            json=payload,
            timeout=Config.MONITORING_TIMEOUT_SEC,
        )
        if 200 <= resp.status_code < 300:
            payload["report"] = {
                "sent": True,
                "sent_at": _utc_now_iso(),
                "server_response": f"{resp.status_code} {resp.reason}".strip(),
            }
            logger.info(
                "Monitoring ingest sent: vehicle=%s status=%s target=%s",
                vehicle_id,
                status_norm,
                target_version,
            )
            return True
        payload["report"] = {
            "sent": False,
            "sent_at": "",
            "server_response": f"{resp.status_code} {resp.reason}".strip(),
        }
        logger.warning(
            "Monitoring ingest failed: status=%s body=%s",
            resp.status_code,
            (resp.text or "")[:240],
        )
        return False
    except Exception as exc:
        payload["report"] = {
            "sent": False,
            "sent_at": "",
            "server_response": f"exception: {exc.__class__.__name__}",
        }
        logger.warning("Monitoring ingest error: %s", exc)
        return False
