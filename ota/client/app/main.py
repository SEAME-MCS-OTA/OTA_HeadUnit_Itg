import os
import json
import logging
import socket
import threading
import time
import struct
import subprocess
import re
import glob
from datetime import datetime
from typing import Dict, Any, Optional, Callable, Tuple
from urllib.parse import urlparse
from flask import Flask, jsonify, request

try:
    import fcntl  # type: ignore
except Exception:
    fcntl = None  # type: ignore

try:
    import paho.mqtt.client as mqtt  # type: ignore
except Exception:
    mqtt = None  # type: ignore

from .ota_logic import (
    build_event,
    download_with_retries,
    cleanup_old_bundles,
    verify_bundle_integrity,
    verify_command_signature,
    post_write_verify,
    rauc_status_json,
    parse_rauc_status,
    rauc_install,
    rauc_mark_good,
    state,
    PHASE_DOWNLOAD,
    PHASE_APPLY,
    PHASE_REBOOT,
    PHASE_COMMIT,
    EVENT_START,
    EVENT_OK,
    EVENT_FAIL,
    load_config,
    _write_event,
    _post_event,
    start_queue_flusher,
)
from .mqtt_utils import parse_mqtt_update_command

app = Flask(__name__)
logging.basicConfig(
    level=getattr(logging, os.environ.get("LOG_LEVEL", "INFO").upper(), logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


def _append_runtime_log(line: str) -> None:
    try:
        os.makedirs("/data/log/ui", exist_ok=True)
        ts = datetime.now().astimezone().isoformat(timespec="seconds")
        with open("/data/log/ui/ota-backend-requests.log", "a", encoding="utf-8") as f:
            f.write(f"{ts} {line}\n")
    except Exception:
        pass


@app.before_request
def _log_request():
    _append_runtime_log(f"{request.method} {request.path}")


@app.after_request
def _add_cors_headers(resp):
    # Allow QML (qrc/file origin) and local tools to call backend endpoints.
    resp.headers["Access-Control-Allow-Origin"] = "*"
    resp.headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS"
    resp.headers["Access-Control-Allow-Headers"] = "Content-Type"
    return resp


def _normalize_ip(raw: str) -> Optional[str]:
    ip = str(raw or "").strip()
    if not ip or ip.startswith("127."):
        return None
    return ip


def _first_ipv4_from_text(text: str) -> Optional[str]:
    # Accept first valid IPv4 token from arbitrary command output.
    for match in re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b", str(text or "")):
        try:
            socket.inet_aton(match)
        except OSError:
            continue
        ip = _normalize_ip(match)
        if ip:
            return ip
    return None


def _ip_tool_candidates() -> list[str]:
    candidates = ["/usr/sbin/ip", "/sbin/ip", "/usr/bin/ip", "/bin/ip", "ip"]
    seen = set()
    resolved = []
    for c in candidates:
        if c in seen:
            continue
        seen.add(c)
        if c == "ip" or os.path.exists(c):
            resolved.append(c)
    return resolved

def _default_iface() -> Optional[str]:
    try:
        with open("/proc/net/route", "r", encoding="utf-8") as f:
            for line in f.readlines()[1:]:
                cols = line.strip().split()
                if len(cols) < 11:
                    continue
                iface, destination, flags = cols[0], cols[1], cols[3]
                if destination != "00000000":
                    continue
                if (int(flags, 16) & 0x2) == 0:
                    continue
                return iface
    except Exception:
        pass
    return None

def _iface_ipv4(iface: str) -> Optional[str]:
    if fcntl is None:
        return None
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        packed = struct.pack("256s", iface[:15].encode("utf-8"))
        res = fcntl.ioctl(sock.fileno(), 0x8915, packed)  # SIOCGIFADDR
        ip = _normalize_ip(socket.inet_ntoa(res[20:24]))
        if ip:
            return ip
    except Exception:
        return None
    finally:
        sock.close()
    return None

def _first_cmd_ip() -> Optional[str]:
    # Try multiple commands to support both full iproute2 and minimal userspace.
    commands = []
    for ip_tool in _ip_tool_candidates():
        commands.append([ip_tool, "-4", "addr", "show", "scope", "global"])
        commands.append([ip_tool, "-4", "addr", "show"])
        commands.append([ip_tool, "addr", "show"])
    commands.append(["hostname", "-I"])
    for cmd in commands:
        try:
            out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)
            ip = _first_ipv4_from_text(out)
            if ip:
                return ip
        except Exception:
            continue
    return None


def _fib_trie_ip() -> Optional[str]:
    # Fallback for images where ip/ifconfig options are limited.
    try:
        with open("/proc/net/fib_trie", "r", encoding="utf-8") as f:
            ip = _first_ipv4_from_text(f.read())
            if ip:
                return ip
    except Exception:
        pass
    return None

def _get_ip_and_source() -> tuple[str, str]:
    cmd_ip = _first_cmd_ip()
    if cmd_ip:
        return cmd_ip, "cmd"

    # Prefer interface IPs (works without internet egress).
    seen = set()
    candidates = []
    dflt = _default_iface()
    if dflt:
        candidates.append(dflt)
    candidates.extend(["wlan0", "eth0"])

    for iface in candidates:
        if not iface or iface in seen:
            continue
        seen.add(iface)
        ip = _iface_ipv4(iface)
        if ip:
            return ip, f"ioctl:{iface}"

    # Fallback: route-based local address.
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = _normalize_ip(s.getsockname()[0])
        s.close()
        if ip:
            return ip, "route-socket"
    except Exception:
        pass

    # Last resort.
    try:
        ip = _normalize_ip(socket.gethostbyname(socket.gethostname()))
        if ip:
            return ip, "hostname"
    except Exception:
        pass

    fib_ip = _fib_trie_ip()
    if fib_ip:
        return fib_ip, "fib-trie"

    return "-", "none"


def _get_ip() -> str:
    return _get_ip_and_source()[0]


def _slot_from_hint(raw: str) -> Optional[str]:
    s = str(raw or "").strip().lower()
    if not s:
        return None

    if s in ("a", "slot-a", "rootfsa", "rootfs.0", "rootfs0"):
        return "A"
    if s in ("b", "slot-b", "rootfsb", "rootfs.1", "rootfs1"):
        return "B"

    if "rootfsa" in s or "rootfs.0" in s:
        return "A"
    if "rootfsb" in s or "rootfs.1" in s:
        return "B"

    # Common A/B partition layout used in this image: p2=A, p3=B
    if re.search(r"(?:^|/)mmcblk\d+p2(?:\D|$)", s) or re.search(r"(?:^|/)sd[a-z]2(?:\D|$)", s):
        return "A"
    if re.search(r"(?:^|/)mmcblk\d+p3(?:\D|$)", s) or re.search(r"(?:^|/)sd[a-z]3(?:\D|$)", s):
        return "B"

    # PARTUUID layout used by Raspberry Pi cmdline (e.g. PARTUUID=xxxx-02 / xxxx-03)
    if re.search(r"partuuid=[0-9a-f-]+-0*2(?:\D|$)", s) or re.search(r"/by-partuuid/[0-9a-f-]+-0*2(?:\D|$)", s):
        return "A"
    if re.search(r"partuuid=[0-9a-f-]+-0*3(?:\D|$)", s) or re.search(r"/by-partuuid/[0-9a-f-]+-0*3(?:\D|$)", s):
        return "B"

    return None


def _infer_current_slot() -> tuple[Optional[str], str]:
    # 1) RAUC runtime hint files
    for path in ("/run/rauc/slot", "/run/rauc/booted"):
        try:
            with open(path, "r", encoding="utf-8") as f:
                slot = _slot_from_hint(f.read())
                if slot:
                    return slot, f"hint:{path}"
        except Exception:
            pass

    # 2) Kernel cmdline hints
    try:
        with open("/proc/cmdline", "r", encoding="utf-8") as f:
            cmdline = f.read().strip()

        m_slot = re.search(r"(?:^|\s)rauc\.slot=([^\s]+)", cmdline)
        if m_slot:
            slot = _slot_from_hint(m_slot.group(1))
            if slot:
                return slot, "cmdline:rauc.slot"

        m_root = re.search(r"(?:^|\s)root=([^\s]+)", cmdline)
        if m_root:
            slot = _slot_from_hint(m_root.group(1))
            if slot:
                return slot, "cmdline:root"
    except Exception:
        pass

    # 3) Mounted root source
    try:
        with open("/proc/mounts", "r", encoding="utf-8") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 2 and parts[1] == "/":
                    slot = _slot_from_hint(parts[0])
                    if slot:
                        return slot, "proc-mounts:/"
                    break
    except Exception:
        pass

    return None, "none"


def _is_unknown_version(raw: Any) -> bool:
    s = str(raw or "").strip().lower()
    return s in ("", "-", "unknown", "none", "n/a")


def _infer_current_version_from_ota_logs(log_root: str) -> Optional[str]:
    root = str(log_root or "").strip() or "/data/log/ota"
    try:
        pattern = os.path.join(root, "*", "events.jsonl")
        files = [p for p in glob.glob(pattern) if os.path.isfile(p)]
        files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    except Exception:
        return None

    # Inspect recent OTA event files first.
    for path in files[:20]:
        try:
            with open(path, "r", encoding="utf-8") as f:
                lines = f.read().splitlines()
        except Exception:
            continue

        for line in reversed(lines):
            line = line.strip()
            if not line:
                continue
            try:
                evt = json.loads(line)
            except Exception:
                continue

            ota = evt.get("ota", {}) if isinstance(evt, dict) else {}
            event = str(ota.get("event") or "").strip().upper()
            phase = str(ota.get("phase") or "").strip().upper()
            target = str(ota.get("target_version") or "").strip()
            current = str(ota.get("current_version") or "").strip()

            # Prefer successful apply/commit records.
            if event == "OK" and phase in ("REBOOT", "COMMIT", "APPLY"):
                if not _is_unknown_version(target):
                    return target
                if not _is_unknown_version(current):
                    return current

            # Conservative fallback: keep current_version inference stable.
            # Do not use target_version from non-final events (e.g. DOWNLOAD START),
            # otherwise UI may show current==target before apply/reboot is complete.
            if not _is_unknown_version(current):
                return current

    return None

ACTIVE_PHASES = (PHASE_DOWNLOAD, PHASE_APPLY, PHASE_REBOOT, PHASE_COMMIT)
_ota_start_lock = threading.Lock()


def _cfg_bool(value: Any, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def _cfg_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except Exception:
        return default


def _format_mqtt_topic(template: str, device_id: str) -> str:
    topic = str(template or "").strip()
    if not topic:
        return ""
    try:
        return topic.format(vehicle_id=device_id, device_id=device_id)
    except Exception:
        return topic.replace("{vehicle_id}", device_id).replace("{device_id}", device_id)


def _safe_cmd_output(cmd: list[str], timeout_sec: float = 1.0) -> str:
    try:
        return subprocess.check_output(
            cmd,
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=timeout_sec,
        )
    except Exception:
        return ""


def _default_gateway_and_iface() -> tuple[str, str]:
    out = _safe_cmd_output(["ip", "route", "show", "default"])
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        gw = ""
        iface = ""
        m = re.search(r"\bvia\s+(\d{1,3}(?:\.\d{1,3}){3})\b", line)
        if m:
            gw = m.group(1)
        parts = line.split()
        if "dev" in parts:
            idx = parts.index("dev")
            if idx + 1 < len(parts):
                iface = parts[idx + 1]
        return gw, iface
    return "", ""


def _measure_rssi_dbm(iface: str) -> Optional[int]:
    iface = str(iface or "").strip()
    if not iface:
        return None

    out = _safe_cmd_output(["iw", "dev", iface, "link"], timeout_sec=0.8)
    m = re.search(r"signal:\s*(-?\d+)\s*dBm", out)
    if m:
        try:
            return int(m.group(1))
        except Exception:
            pass

    out = _safe_cmd_output(["iwconfig", iface], timeout_sec=0.8)
    m = re.search(r"Signal level[=:\s]*(-?\d+)\s*dBm", out)
    if m:
        try:
            return int(m.group(1))
        except Exception:
            pass

    return None


def _measure_latency_ms(target_ip: str) -> Optional[int]:
    target = str(target_ip or "").strip()
    if not target:
        return None
    out = _safe_cmd_output(["ping", "-c", "1", "-W", "1", target], timeout_sec=1.8)
    m = re.search(r"time[=<]\s*([0-9.]+)\s*ms", out)
    if not m:
        return None
    try:
        return int(round(float(m.group(1))))
    except Exception:
        return None


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
    """
    Create a paho client compatible with both v1.x and v2.x.
    v2.x may require callback_api_version and defaults to v2 callbacks.
    """
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
    ):
        self.cfg = cfg
        self.on_update_request = on_update_request
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
            _append_runtime_log("mqtt disabled")
            return
        if mqtt is None:
            logger.warning("MQTT is enabled but paho-mqtt is not installed")
            _append_runtime_log("mqtt unavailable: paho-mqtt missing")
            return
        if not self.device_id:
            logger.warning("MQTT is enabled but device_id is empty; command subscription skipped")
            _append_runtime_log("mqtt disabled: empty device_id")
            return

        try:
            client = _create_mqtt_client(self.client_id)
            self.configure_lwt(client)
            client.on_connect = self._on_connect
            client.on_disconnect = self._on_disconnect
            client.on_message = self._on_message

            if self.username:
                client.username_pw_set(self.username, self.password)

            # Never block backend startup on broker reachability.
            # connect_async() schedules connection in the network loop thread.
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
            _append_runtime_log(
                f"mqtt connecting host={self.broker_host}:{self.broker_port} "
                f"cmd_topic={self._topic_cmd()} announce_topic={self._topic_announce()} qos={self.qos}"
            )
        except Exception as ex:
            logger.warning("MQTT start failed: %s", ex)
            _append_runtime_log(f"mqtt start failed: {ex.__class__.__name__}")

    def stop(self) -> None:
        if not self.client:
            return
        try:
            if self.connected:
                self.publish_offline("CLIENT_STOP")
            self.client.loop_stop()
            self.client.disconnect()
        except Exception:
            pass
        self.connected = False

    def _on_connect(self, client, userdata, flags, rc):
        if rc != 0:
            self.connected = False
            _append_runtime_log(f"mqtt connect failed rc={rc}")
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
            _append_runtime_log("mqtt connect failed: empty subscribe topics")
            return

        for topic in topics:
            client.subscribe(topic, qos=self.qos)
        self.connected = True
        _append_runtime_log(f"mqtt connected sub={','.join(topics)}")

    def _on_disconnect(self, client, userdata, rc):
        self.connected = False
        _append_runtime_log(f"mqtt disconnected rc={rc}")

    def _on_message(self, client, userdata, msg):
        try:
            payload_text = msg.payload.decode("utf-8", errors="replace")
            data = json.loads(payload_text)
        except Exception as ex:
            _append_runtime_log(f"mqtt invalid payload topic={msg.topic} err={ex.__class__.__name__}")
            return

        if msg.topic == self._topic_announce():
            self._handle_release_announce(data)
            return

        req = parse_mqtt_update_command(
            data,
            default_ota_id_prefix=f"{self.device_id or 'device'}-mqtt",
        )
        if not req:
            _append_runtime_log(f"mqtt ignored payload topic={msg.topic}")
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
            _append_runtime_log(
                f"mqtt accepted ota_id={req['ota_id']} target={req['target_version']}"
            )
        else:
            _append_runtime_log(
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
                if result.rc != mqtt.MQTT_ERR_SUCCESS:
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
            _append_runtime_log(f"mqtt will_set failed: {ex.__class__.__name__}")

    def publish_offline(self, reason: str = "CLIENT_STOP") -> None:
        self.publish_status("offline", str(state.current_version or "unknown"), reason)

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
            _append_runtime_log(
                f"mqtt register published topic={topic} trigger={trigger} release={release_id or '-'}"
            )
        else:
            _append_runtime_log(
                f"mqtt register publish failed topic={topic} trigger={trigger} release={release_id or '-'}"
            )
        return ok


CFG_PATH = os.environ.get("OTA_BACKEND_CONFIG", "/etc/ota-backend/config.json")
CFG: Dict[str, Any] = load_config(CFG_PATH)
MQTT_BRIDGE: Optional[MQTTCommandBridge] = None

_stop_event = threading.Event()
start_queue_flusher(CFG, _stop_event)
_mqtt_heartbeat_started = False

@app.get("/health")
def health():
    return jsonify({
        "ok": True,
        "mqtt_enabled": bool(MQTT_BRIDGE and MQTT_BRIDGE.enabled),
        "mqtt_connected": bool(MQTT_BRIDGE and MQTT_BRIDGE.is_connected()),
    })

@app.get("/ota/status")
def ota_status():
    try:
        status = parse_rauc_status(rauc_status_json())
    except Exception:
        status = {"compatible": None, "current_slot": None, "slots": []}

    try:
        ip_address, ip_source = _get_ip_and_source()
    except Exception:
        ip_address, ip_source = "-", "exception"

    current_slot = status.get("current_slot")
    slot_source = "rauc"
    if not current_slot:
        inferred_slot, inferred_from = _infer_current_slot()
        if inferred_slot:
            current_slot = inferred_slot
            slot_source = inferred_from
        else:
            slot_source = "none"

    slots = status.get("slots", [])
    if not isinstance(slots, list):
        slots = []
    if not slots and current_slot in ("A", "B"):
        # UI fallback: show A/B even when RAUC JSON is unavailable.
        slots = [
            {
                "name": "rootfs.0",
                "state": "booted" if current_slot == "A" else "inactive",
                "bootname": "A",
                "device": "/dev/mmcblk0p2",
            },
            {
                "name": "rootfs.1",
                "state": "booted" if current_slot == "B" else "inactive",
                "bootname": "B",
                "device": "/dev/mmcblk0p3",
            },
        ]

    current_version = state.current_version
    if _is_unknown_version(current_version):
        inferred_version = _infer_current_version_from_ota_logs(CFG.get("ota_log_dir", "/data/log/ota"))
        if inferred_version and not _is_unknown_version(inferred_version):
            current_version = inferred_version
            state.current_version = inferred_version

    _append_runtime_log(f"status ip={ip_address} src={ip_source} slot={current_slot or '-'} slot_src={slot_source}")
    return jsonify({
        "ts": datetime.now().astimezone().isoformat(timespec="seconds"),
        "compatible": status.get("compatible"),
        "current_slot": current_slot,
        "slots": slots,
        "ota_id": state.active_ota_id,
        "ota_log": state.ota_log,
        "current_version": current_version,
        "target_version": state.target_version,
        "phase": state.phase,
        "event": state.event,
        "last_error": state.last_error,
        "ip_address": ip_address,
        "ip": ip_address,
        "ip_source": ip_source,
        "slot_source": slot_source,
        "device_id": CFG.get("device_id"),
    })

@app.post("/ota/start")
def ota_start():
    req = request.get_json(silent=True) or {}
    ota_id = str(req.get("ota_id", "")).strip()
    url = str(req.get("url", "")).strip()
    target_version = str(req.get("target_version", "")).strip()
    expected_sha256 = str(req.get("expected_sha256") or req.get("sha256") or "").strip().lower()
    expected_size = req.get("expected_size")
    signature = req.get("signature") if isinstance(req.get("signature"), dict) else None

    if not ota_id or not url or not target_version:
        return jsonify({"detail": "ota_id, url, target_version are required"}), 400

    ok, reason = _start_ota_job(
        ota_id,
        url,
        target_version,
        "api",
        expected_sha256,
        expected_size,
        signature,
    )
    if not ok:
        return jsonify({"detail": reason}), 409
    return jsonify({"ok": True})


def _publish_mqtt_status(status: str, target_version: str, message: str = "") -> None:
    if MQTT_BRIDGE:
        MQTT_BRIDGE.publish_status(status, target_version, message)


def _publish_mqtt_progress(target_version: str, progress: int, message: str = "") -> None:
    if MQTT_BRIDGE:
        MQTT_BRIDGE.publish_progress(target_version, progress, message)


def _start_ota_job(
    ota_id: str,
    url: str,
    target_version: str,
    trigger_source: str,
    expected_sha256: str = "",
    expected_size: Optional[int] = None,
    signature: Optional[Dict[str, Any]] = None,
) -> Tuple[bool, str]:
    ota_id = str(ota_id or "").strip()
    url = str(url or "").strip()
    target_version = str(target_version or "").strip()
    trigger_source = str(trigger_source or "api").strip() or "api"
    expected_sha256 = str(expected_sha256 or "").strip().lower()
    normalized_expected_size: Optional[int] = None
    try:
        if expected_size is not None and str(expected_size).strip() != "":
            normalized_expected_size = int(expected_size)
    except Exception:
        normalized_expected_size = None
    signature_obj = signature if isinstance(signature, dict) else None

    if not ota_id or not url or not target_version:
        return False, "ota_id, url, target_version are required"

    with _ota_start_lock:
        if state.phase in ACTIVE_PHASES:
            return False, "OTA already running"
        state.active_ota_id = ota_id
        state.target_version = target_version
        state.last_error = None
        state.phase = PHASE_DOWNLOAD
        state.event = EVENT_START
        state.ota_log = []

    def _run():
        ota_log = []

        def _log(msg: str):
            ota_log.append(msg)
            state.ota_log = ota_log[:]

        try:
            state.active_ota_id = ota_id
            state.target_version = target_version
            state.last_error = None

            state.phase = PHASE_DOWNLOAD
            state.event = EVENT_START
            _log("DOWNLOAD START")
            _log(f"SOURCE {trigger_source}")
            if expected_sha256:
                _log(f"EXPECTED SHA256 {expected_sha256}")
            if normalized_expected_size is not None and normalized_expected_size > 0:
                _log(f"EXPECTED SIZE {normalized_expected_size}")
            _publish_mqtt_status("downloading", target_version, f"DOWNLOAD START source={trigger_source}")
            _publish_mqtt_progress(target_version, 5, "Downloading bundle")
            event = build_event(CFG, ota_id, state.current_version, target_version,
                                PHASE_DOWNLOAD, EVENT_START, {}, ota_log)
            _write_event(CFG, ota_id, event)
            _post_event(CFG, event)

            sig_ok, sig_code, sig_msg = verify_command_signature(
                cfg=CFG,
                ota_id=ota_id,
                url=url,
                target_version=target_version,
                expected_sha256=expected_sha256,
                expected_size=normalized_expected_size,
                signature=signature_obj,
            )
            if not sig_ok:
                state.event = EVENT_FAIL
                state.last_error = sig_code or "SIGNATURE_VERIFY_FAILED"
                _log(f"SIGNATURE FAIL code={state.last_error} detail={sig_msg}")
                error = {"code": state.last_error, "message": sig_msg, "retryable": False}
                event = build_event(
                    CFG,
                    ota_id,
                    state.current_version,
                    target_version,
                    PHASE_DOWNLOAD,
                    EVENT_FAIL,
                    error,
                    ota_log,
                )
                _write_event(CFG, ota_id, event)
                _post_event(CFG, event)
                _publish_mqtt_status("failed", target_version, f"Signature verify failed: {sig_msg}")
                state.phase = None
                return
            if sig_msg:
                _log(f"SIGNATURE OK {sig_msg}")

            bundle_dir = CFG.get("bundle_dir", "/data/ota")
            bundle_path = os.path.join(bundle_dir, f"{ota_id}.raucb")

            removed = cleanup_old_bundles(
                bundle_dir=bundle_dir,
                keep=int(CFG.get("bundle_keep", 0)),
                preserve=[bundle_path],
            )
            if removed:
                _log(f"CLEANUP OLD_BUNDLES removed={removed}")

            err_code, last_status = download_with_retries(
                url,
                bundle_path,
                int(CFG.get("download_retries", 3)),
                int(CFG.get("download_timeout_sec", 30)),
                _log,
            )
            if err_code == "NO_SPACE":
                # Retry once after aggressive cleanup (keeps only current target path).
                removed_extra = cleanup_old_bundles(
                    bundle_dir=bundle_dir,
                    keep=0,
                    preserve=[bundle_path],
                )
                if removed_extra:
                    _log(f"CLEANUP RETRY removed={removed_extra}")
                _log("DOWNLOAD RETRY after NO_SPACE")
                err_code, last_status = download_with_retries(
                    url,
                    bundle_path,
                    int(CFG.get("download_retries", 1)),
                    int(CFG.get("download_timeout_sec", 30)),
                    _log,
                )
            if err_code:
                state.event = EVENT_FAIL
                state.last_error = err_code
                if err_code == "HTTP_5XX":
                    msg = f"Server error: {last_status} Service Unavailable" if last_status else "Server error: 5xx"
                elif err_code == "NO_SPACE":
                    msg = "No space left on bundle storage"
                elif err_code == "IO_ERROR":
                    msg = "Storage I/O error during download"
                else:
                    msg = "Download error"
                error = {"code": err_code, "message": msg, "retryable": err_code == "HTTP_5XX"}
                event = build_event(CFG, ota_id, state.current_version, target_version,
                                    PHASE_DOWNLOAD, EVENT_FAIL, error, ota_log)
                _write_event(CFG, ota_id, event)
                _post_event(CFG, event)
                _publish_mqtt_status("failed", target_version, msg)
                state.phase = None
                return

            verify_ok, verify_code, verify_msg = verify_bundle_integrity(
                bundle_path=bundle_path,
                expected_sha256=expected_sha256,
                expected_size=normalized_expected_size,
                require_sha256=_cfg_bool(CFG.get("require_sha256"), True),
            )
            if not verify_ok:
                state.event = EVENT_FAIL
                state.last_error = verify_code or "VERIFY_FAILED"
                _log(f"VERIFY FAIL code={state.last_error} detail={verify_msg}")
                error = {"code": state.last_error, "message": verify_msg, "retryable": False}
                event = build_event(
                    CFG,
                    ota_id,
                    state.current_version,
                    target_version,
                    PHASE_DOWNLOAD,
                    EVENT_FAIL,
                    error,
                    ota_log,
                )
                _write_event(CFG, ota_id, event)
                _post_event(CFG, event)
                _publish_mqtt_status("failed", target_version, verify_msg)
                state.phase = None
                return
            _log("VERIFY OK")

            _publish_mqtt_progress(target_version, 40, "Download complete")
            state.phase = PHASE_APPLY
            state.event = EVENT_START
            _log("APPLY START")
            _publish_mqtt_status("installing", target_version, "APPLY START")
            _publish_mqtt_progress(target_version, 70, "Applying bundle")
            event = build_event(CFG, ota_id, state.current_version, target_version,
                                PHASE_APPLY, EVENT_START, {}, ota_log)
            _write_event(CFG, ota_id, event)
            _post_event(CFG, event)

            rc = rauc_install(bundle_path)
            if rc != 0:
                state.event = EVENT_FAIL
                state.last_error = "RAUC_INSTALL"
                error = {"code": "RAUC_INSTALL", "message": "RAUC install failed", "retryable": False}
                event = build_event(CFG, ota_id, state.current_version, target_version,
                                    PHASE_APPLY, EVENT_FAIL, error, ota_log)
                _write_event(CFG, ota_id, event)
                _post_event(CFG, event)
                _publish_mqtt_status("failed", target_version, "RAUC install failed")
                state.phase = None
                return

            post_ok, post_code, post_msg = post_write_verify(CFG, _log)
            if not post_ok:
                state.event = EVENT_FAIL
                state.last_error = post_code or "POST_WRITE_FAILED"
                _log(f"POST_WRITE FAIL code={state.last_error} detail={post_msg}")
                error = {"code": state.last_error, "message": post_msg, "retryable": False}
                event = build_event(
                    CFG,
                    ota_id,
                    state.current_version,
                    target_version,
                    PHASE_APPLY,
                    EVENT_FAIL,
                    error,
                    ota_log,
                )
                _write_event(CFG, ota_id, event)
                _post_event(CFG, event)
                _publish_mqtt_status("failed", target_version, f"Post-write verify failed: {post_msg}")
                state.phase = None
                return
            _log("POST_WRITE OK")

            state.phase = PHASE_REBOOT
            state.event = EVENT_OK
            state.current_version = target_version
            _log("APPLY OK")
            _publish_mqtt_progress(target_version, 90, "Apply complete")
            event = build_event(CFG, ota_id, state.current_version, target_version,
                                PHASE_REBOOT, EVENT_OK, {}, ota_log)
            _write_event(CFG, ota_id, event)
            _post_event(CFG, event)

            if bool(CFG.get("reboot_after_apply", False)):
                _publish_mqtt_status("completed", target_version, "APPLY OK, rebooting")
                _publish_mqtt_progress(target_version, 100, "Completed")
                os.system("systemctl reboot")
                return

            state.phase = PHASE_COMMIT
            state.event = EVENT_START
            _log("COMMIT START")
            _publish_mqtt_status("installing", target_version, "COMMIT START")
            event = build_event(CFG, ota_id, state.current_version, target_version,
                                PHASE_COMMIT, EVENT_START, {}, ota_log)
            _write_event(CFG, ota_id, event)
            _post_event(CFG, event)

            if bool(CFG.get("mark_good_on_commit", True)):
                rauc_mark_good()

            state.event = EVENT_OK
            _log("COMMIT OK")
            _publish_mqtt_status("completed", target_version, "COMMIT OK")
            _publish_mqtt_progress(target_version, 100, "Completed")
            event = build_event(CFG, ota_id, state.current_version, target_version,
                                PHASE_COMMIT, EVENT_OK, {}, ota_log)
            _write_event(CFG, ota_id, event)
            _post_event(CFG, event)
            state.phase = None
        except Exception as ex:
            state.event = EVENT_FAIL
            state.last_error = "INTERNAL"
            _log(f"INTERNAL ERROR {ex.__class__.__name__}")
            error = {"code": "INTERNAL", "message": str(ex), "retryable": False}
            event = build_event(
                CFG,
                ota_id,
                state.current_version,
                target_version,
                state.phase or "UNKNOWN",
                EVENT_FAIL,
                error,
                ota_log,
            )
            _write_event(CFG, ota_id, event)
            _post_event(CFG, event)
            _publish_mqtt_status("failed", target_version, f"INTERNAL: {ex.__class__.__name__}")
            state.phase = None

    try:
        t = threading.Thread(target=_run, daemon=True)
        t.start()
        _append_runtime_log(
            f"ota start source={trigger_source} ota_id={ota_id} target={target_version} url={url}"
        )
        return True, "started"
    except Exception as ex:
        with _ota_start_lock:
            state.phase = None
            state.event = EVENT_FAIL
            state.last_error = "THREAD_START"
        _append_runtime_log(f"ota start failed source={trigger_source} err={ex.__class__.__name__}")
        return False, "failed to start ota worker"

@app.post("/ota/reboot")
def ota_reboot():
    os.system("systemctl reboot")
    return jsonify({"ok": True})


def _init_mqtt_bridge() -> None:
    global MQTT_BRIDGE
    if MQTT_BRIDGE is None:
        MQTT_BRIDGE = MQTTCommandBridge(CFG, _start_ota_job)
    MQTT_BRIDGE.start()


def _start_mqtt_heartbeat() -> None:
    global _mqtt_heartbeat_started
    if _mqtt_heartbeat_started:
        return

    enabled = _cfg_bool(CFG.get("mqtt_publish_heartbeat"), default=True)
    if not enabled:
        _append_runtime_log("mqtt heartbeat disabled (mqtt_publish_heartbeat=false)")
        return

    interval_sec = _cfg_int(CFG.get("mqtt_heartbeat_sec", 20), 20)
    if interval_sec <= 0:
        _append_runtime_log("mqtt heartbeat disabled")
        return

    def _run():
        # Publish register heartbeat so OTA server can keep device last_seen fresh
        # without creating noisy OTA status history rows.
        while not _stop_event.is_set():
            _stop_event.wait(interval_sec)
            if _stop_event.is_set():
                return

            bridge = MQTT_BRIDGE
            if not bridge or not bridge.enabled or not bridge.is_connected():
                continue
            if not bridge.should_publish_presence_heartbeat():
                continue
            if state.phase in ACTIVE_PHASES:
                continue

            bridge.publish_register("heartbeat", version=str(state.current_version or "unknown"))

    threading.Thread(target=_run, daemon=True).start()
    _mqtt_heartbeat_started = True
    _append_runtime_log(f"mqtt heartbeat started interval={interval_sec}s")


def main():
    _init_mqtt_bridge()
    _start_mqtt_heartbeat()
    app.run(host="0.0.0.0", port=8080)
