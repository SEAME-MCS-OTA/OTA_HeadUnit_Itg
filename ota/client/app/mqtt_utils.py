import json
import logging
import re
import threading
import time
from datetime import datetime
from typing import Any, Callable, Dict, Optional, Tuple
from urllib.parse import urlparse

try:
    import paho.mqtt.client as mqtt  # type: ignore
except Exception:
    mqtt = None  # type: ignore

from .IP_helpers import _default_iface, _get_ip_and_source
from .ota_logic import (
    _cfg_bool,
    _cfg_int,
    _default_gateway_and_iface,
    _measure_latency_ms,
    _measure_rssi_dbm,
    PHASE_APPLY,
    PHASE_COMMIT,
    PHASE_DOWNLOAD,
    PHASE_REBOOT,
    state,
)

logger = logging.getLogger(__name__)

ACTIVE_PHASES = (PHASE_DOWNLOAD, PHASE_APPLY, PHASE_REBOOT, PHASE_COMMIT)
_ota_start_lock = threading.Lock()


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


def _format_mqtt_topic(template: str, device_id: str) -> str:
    topic = str(template or "").strip()
    if not topic:
        return ""
    try:
        return topic.format(vehicle_id=device_id, device_id=device_id)
    except Exception:
        return topic.replace("{vehicle_id}", device_id).replace("{device_id}", device_id)


def _mqtt_network_snapshot() -> Dict[str, Any]:
    ip, ip_source = _get_ip_and_source()
    gw_ip, gw_iface = _default_gateway_and_iface()
    iface = gw_iface or _default_iface() or "wlan0"
    rssi_dbm = _measure_rssi_dbm(iface)
    latency_ms = _measure_latency_ms(gw_ip)
    return {
        "iface": iface or "wlan0",
        "ip": "" if ip == "-" else ip,
        "ip_source": ip_source,
        "rssi_dbm": int(rssi_dbm) if rssi_dbm is not None else 0,
        "latency_ms": int(latency_ms) if latency_ms is not None else 0,
        "gateway_reachable": latency_ms is not None,
    }


def _host_from_url(raw_url: Any) -> str:
    text = str(raw_url or "").strip()
    if not text:
        return ""
    try:
        parsed = urlparse(text)
        return str(parsed.hostname or "").strip()
    except Exception:
        return ""


def _create_mqtt_client(client_id: str):
    if mqtt is None:
        raise RuntimeError("paho-mqtt unavailable")
    kwargs = {
        "client_id": client_id,
        "protocol": mqtt.MQTTv311,
        "clean_session": True,
    }
    callback_api = getattr(mqtt, "CallbackAPIVersion", None)
    if callback_api is not None:
        try:
            return mqtt.Client(callback_api_version=callback_api.VERSION1, **kwargs)
        except Exception:
            pass
    return mqtt.Client(**kwargs)


class MQTTCommandBridge:
    def __init__(
        self,
        cfg: Dict[str, Any],
        on_update_request: Callable[
            [str, str, str, str, str, Optional[int], Optional[Dict[str, Any]]],
            Tuple[bool, str],
        ],
        append_runtime_log: Callable[[str], None],
    ):
        self.cfg = cfg
        self.on_update_request = on_update_request
        self._append_runtime_log = append_runtime_log
        self.enabled = _cfg_bool(cfg.get("mqtt_enabled"), default=False)
        raw_broker_host = str(cfg.get("mqtt_broker_host", "localhost")).strip()
        collector_host = _host_from_url(cfg.get("collector_url"))
        if raw_broker_host.lower() in ("", "localhost", "127.0.0.1", "::1") and collector_host:
            self.broker_host = collector_host
        else:
            self.broker_host = raw_broker_host
        self.broker_port = _cfg_int(cfg.get("mqtt_broker_port", 1883), 1883)
        self.keepalive = _cfg_int(cfg.get("mqtt_keepalive_sec", 60), 60)
        self.qos = _cfg_int(cfg.get("mqtt_qos", 1), 1)
        self.username = str(cfg.get("mqtt_username", "")).strip()
        self.password = str(cfg.get("mqtt_password", "")).strip()
        self.device_id = str(cfg.get("device_id", "")).strip()
        default_client_id = f"ota-backend-{self.device_id or 'device'}"
        self.client_id = str(cfg.get("mqtt_client_id", default_client_id)).strip() or default_client_id
        self.topic_cmd_template = str(cfg.get("mqtt_topic_cmd", "ota/{vehicle_id}/cmd"))
        self.topic_status_template = str(cfg.get("mqtt_topic_status", "ota/{vehicle_id}/status"))
        self.topic_progress_template = str(cfg.get("mqtt_topic_progress", "ota/{vehicle_id}/progress"))
        self.topic_announce_template = str(cfg.get("mqtt_topic_release_announce", "ota/releases/announce"))
        self.topic_register_template = str(cfg.get("mqtt_topic_vehicle_register", "ota/vehicles/register"))
        self.register_on_announce = _cfg_bool(cfg.get("mqtt_register_on_announce"), default=True)
        self.heartbeat_after_announce = _cfg_bool(
            cfg.get("mqtt_presence_heartbeat_after_announce"), default=True
        )
        self.client = None
        self.connected = False
        self._lock = threading.Lock()
        self._last_announce_key = ""
        self._last_announce_at = 0.0
        self._presence_announced = False

    def _topic_cmd(self) -> str:
        return _format_mqtt_topic(self.topic_cmd_template, self.device_id)

    def _topic_status(self) -> str:
        return _format_mqtt_topic(self.topic_status_template, self.device_id)

    def _topic_progress(self) -> str:
        return _format_mqtt_topic(self.topic_progress_template, self.device_id)

    def _topic_announce(self) -> str:
        return str(self.topic_announce_template or "").strip()

    def _topic_register(self) -> str:
        return str(self.topic_register_template or "").strip()

    def is_connected(self) -> bool:
        return bool(self.connected)

    def start(self) -> None:
        if not self.enabled:
            self._append_runtime_log("mqtt disabled")
            return
        if mqtt is None:
            logger.warning("MQTT is enabled but paho-mqtt is not installed")
            self._append_runtime_log("mqtt unavailable: paho-mqtt missing")
            return
        if not self.device_id:
            logger.warning("MQTT is enabled but device_id is empty; command subscription skipped")
            self._append_runtime_log("mqtt disabled: empty device_id")
            return

        try:
            client = _create_mqtt_client(self.client_id)
            self.configure_lwt(client)
            client.on_connect = self._on_connect
            client.on_disconnect = self._on_disconnect
            client.on_message = self._on_message

            if self.username:
                client.username_pw_set(self.username, self.password)

            if hasattr(client, "reconnect_delay_set"):
                try:
                    client.reconnect_delay_set(min_delay=1, max_delay=10)
                except Exception:
                    pass

            if hasattr(client, "connect_async"):
                client.connect_async(self.broker_host, self.broker_port, keepalive=self.keepalive)
            else:
                client.connect(self.broker_host, self.broker_port, keepalive=self.keepalive)
            client.loop_start()
            self.client = client
            self._append_runtime_log(
                f"mqtt connecting host={self.broker_host}:{self.broker_port} "
                f"cmd_topic={self._topic_cmd()} announce_topic={self._topic_announce()} qos={self.qos}"
            )
        except Exception as ex:
            logger.warning("MQTT start failed: %s", ex)
            self._append_runtime_log(f"mqtt start failed: {ex.__class__.__name__}")

    def _on_connect(self, client, userdata, flags, rc):
        if rc != 0:
            self.connected = False
            self._append_runtime_log(f"mqtt connect failed rc={rc}")
            return

        topics = []
        cmd_topic = self._topic_cmd()
        announce_topic = self._topic_announce()
        if cmd_topic:
            topics.append(cmd_topic)
        if announce_topic:
            topics.append(announce_topic)

        if not topics:
            self.connected = False
            self._append_runtime_log("mqtt connect failed: empty subscribe topics")
            return

        for topic in topics:
            client.subscribe(topic, qos=self.qos)
        self.connected = True
        self._append_runtime_log(f"mqtt connected sub={','.join(topics)}")

    def _on_disconnect(self, client, userdata, rc):
        self.connected = False
        self._append_runtime_log(f"mqtt disconnected rc={rc}")

    def _on_message(self, client, userdata, msg):
        try:
            payload_text = msg.payload.decode("utf-8", errors="replace")
            data = json.loads(payload_text)
        except Exception as ex:
            self._append_runtime_log(f"mqtt invalid payload topic={msg.topic} err={ex.__class__.__name__}")
            return

        if msg.topic == self._topic_announce():
            self._handle_release_announce(data)
            return

        req = parse_mqtt_update_command(
            data,
            default_ota_id_prefix=f"{self.device_id or 'device'}-mqtt",
        )
        if not req:
            self._append_runtime_log(f"mqtt ignored payload topic={msg.topic}")
            return

        ok, reason = self.on_update_request(
            req["ota_id"],
            req["url"],
            req["target_version"],
            "mqtt",
            str(req.get("expected_sha256") or "").strip().lower(),
            req.get("expected_size"),
            req.get("signature") if isinstance(req.get("signature"), dict) else None,
        )
        if ok:
            self._presence_announced = True
            self._append_runtime_log(
                f"mqtt accepted ota_id={req['ota_id']} target={req['target_version']}"
            )
        else:
            self._append_runtime_log(
                f"mqtt rejected ota_id={req['ota_id']} reason={reason}"
            )
            self.publish_status("failed", req["target_version"], f"Command rejected: {reason}")

    def _handle_release_announce(self, data: Dict[str, Any]) -> None:
        if not self.register_on_announce:
            return

        release_id = str(data.get("release_id") or data.get("ota_id") or "").strip()
        version = str(data.get("version") or "").strip()
        if not release_id and version:
            release_id = f"version:{version}"
        if not release_id:
            release_id = f"ts:{int(time.time())}"

        now = time.time()
        if release_id == self._last_announce_key and (now - self._last_announce_at) < 10:
            return
        self._last_announce_key = release_id
        self._last_announce_at = now

        ok = self.publish_register("release_announce", release_id=release_id, version=version)
        if ok:
            self._presence_announced = True

    def _publish(self, topic: str, payload: Dict[str, Any]) -> bool:
        if not topic:
            return False
        with self._lock:
            if not self.client or not self.connected:
                return False
            try:
                result = self.client.publish(topic, json.dumps(payload), qos=self.qos)
                success_rc = getattr(mqtt, "MQTT_ERR_SUCCESS", 0)
                if result.rc != success_rc:
                    logger.debug("MQTT publish failed topic=%s rc=%s", topic, result.rc)
                    return False
                return True
            except Exception:
                return False

    def _status_payload(self, status: str, target_version: str, message: str = "") -> Dict[str, Any]:
        network = _mqtt_network_snapshot()
        return {
            "vehicle_id": self.device_id,
            "status": str(status or "").strip(),
            "target_version": str(target_version or "unknown"),
            "message": str(message or ""),
            "timestamp": datetime.utcnow().isoformat(),
            "ota": {
                "current_version": str(state.current_version or ""),
                "target_version": str(target_version or ""),
                "phase": str(state.phase or ""),
                "event": str(state.event or ""),
            },
            "context": {
                "network": network,
            },
        }

    def configure_lwt(self, client) -> None:
        topic = self._topic_status()
        if not topic:
            return
        payload = self._status_payload(
            "offline",
            str(state.current_version or "unknown"),
            "LWT_DISCONNECTED",
        )
        try:
            client.will_set(topic, json.dumps(payload), qos=self.qos, retain=False)
        except Exception as ex:
            self._append_runtime_log(f"mqtt will_set failed: {ex.__class__.__name__}")

    def should_publish_presence_heartbeat(self) -> bool:
        if not self.heartbeat_after_announce:
            return True
        return bool(self._presence_announced)

    def publish_status(self, status: str, target_version: str, message: str = "") -> None:
        payload = self._status_payload(status, target_version, message)
        self._publish(self._topic_status(), payload)

    def publish_progress(self, target_version: str, progress: int, message: str = "") -> None:
        payload = {
            "vehicle_id": self.device_id,
            "target_version": target_version,
            "progress": max(0, min(100, int(progress))),
            "message": message or f"Progress: {progress}%",
            "timestamp": datetime.utcnow().isoformat(),
        }
        self._publish(self._topic_progress(), payload)

    def publish_register(self, trigger: str, release_id: str = "", version: str = "") -> bool:
        network = _mqtt_network_snapshot()
        payload = {
            "vehicle_id": self.device_id,
            "device_id": self.device_id,
            "status": "idle",
            "current_version": str(state.current_version or "unknown"),
            "ip": str(network.get("ip") or ""),
            "context": {"network": network},
            "trigger": str(trigger or ""),
            "release_id": str(release_id or ""),
            "version": str(version or ""),
            "timestamp": datetime.utcnow().isoformat(),
        }
        topic = self._topic_register()
        ok = self._publish(topic, payload)
        if ok:
            self._presence_announced = True
            self._append_runtime_log(
                f"mqtt register published topic={topic} trigger={trigger} release={release_id or '-'}"
            )
        else:
            self._append_runtime_log(
                f"mqtt register publish failed topic={topic} trigger={trigger} release={release_id or '-'}"
            )
        return ok
