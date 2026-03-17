import json
import os
import time
import threading
import subprocess
import errno
import re
import socket
import hashlib
import base64
import tempfile
from datetime import datetime
from typing import Dict, Any, List, Optional, Iterable, Tuple

import requests

PHASE_DOWNLOAD = "DOWNLOAD"
PHASE_APPLY = "APPLY"
PHASE_REBOOT = "REBOOT"
PHASE_COMMIT = "COMMIT"

EVENT_START = "START"
EVENT_OK = "OK"
EVENT_FAIL = "FAIL"

class OtaState:
    def __init__(self):
        self.current_version = "unknown"
        self.target_version = None
        self.phase = None
        self.event = None
        self.last_error = None
        self.active_ota_id = None
        self.ota_log: List[str] = []

state = OtaState()

def load_config(path: str) -> Dict[str, Any]:
    if not os.path.exists(path):
        return {}
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)

def _now_ts() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")

def _day_of_week() -> str:
    return datetime.now().strftime("%a")

def _time_bucket() -> str:
    hour = datetime.now().hour
    if 6 <= hour < 12:
        return "MORNING"
    if 12 <= hour < 18:
        return "AFTERNOON"
    if 18 <= hour < 22:
        return "EVENING"
    return "NIGHT"

def _safe_journal(unit: str, lines: int = 50) -> List[str]:
    try:
        out = subprocess.check_output(
            ["journalctl", "-u", unit, "-n", str(lines), "--no-pager"],
            text=True,
        )
        return [line.strip() for line in out.splitlines() if line.strip()]
    except Exception:
        return []

def _filesystem_evidence(path: str) -> List[Dict[str, Any]]:
    try:
        stat = os.statvfs(path)
        free = stat.f_bavail * stat.f_frsize
        total = stat.f_blocks * stat.f_frsize
        return [{"path": path, "free_bytes": free, "total_bytes": total}]
    except Exception:
        return []


def _cfg_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except Exception:
        return default


def _cfg_bool(value: Any, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def _safe_cmd_output(cmd: List[str], timeout_sec: float = 1.0) -> str:
    try:
        return subprocess.check_output(
            cmd,
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=timeout_sec,
        )
    except Exception:
        return ""


def _network_iface_and_ip() -> Tuple[str, str]:
    # Prefer non-loopback IPv4 from iproute2.
    out = _safe_cmd_output(["ip", "-4", "-o", "addr", "show", "up"])
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        iface = parts[1]
        for token in parts:
            if "/" not in token:
                continue
            ip = token.split("/", 1)[0]
            if re.match(r"^\d{1,3}(?:\.\d{1,3}){3}$", ip) and not ip.startswith("127."):
                return iface, ip

    # Fallback to route socket resolution.
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if ip and not ip.startswith("127."):
            return "wlan0", ip
    except Exception:
        pass

    return "wlan0", "-"


def _default_gateway_and_iface() -> Tuple[str, str]:
    out = _safe_cmd_output(["ip", "route", "show", "default"])
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        m = re.search(r"\bvia\s+(\d{1,3}(?:\.\d{1,3}){3})\b", line)
        gw = m.group(1) if m else ""
        parts = line.split()
        iface = ""
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

    # Most modern images expose RSSI here.
    out = _safe_cmd_output(["iw", "dev", iface, "link"], timeout_sec=0.8)
    m = re.search(r"signal:\s*(-?\d+)\s*dBm", out)
    if m:
        try:
            return int(m.group(1))
        except Exception:
            pass

    # Fallback for legacy userspace.
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

    # BusyBox ping: -W seconds. iputils ping: -W timeout.
    out = _safe_cmd_output(["ping", "-c", "1", "-W", "1", target], timeout_sec=1.8)
    m = re.search(r"time[=<]\s*([0-9.]+)\s*ms", out)
    if m:
        try:
            return int(round(float(m.group(1))))
        except Exception:
            pass
    return None


def _gateway_reachable(default: bool = True) -> bool:
    out = _safe_cmd_output(["ip", "route", "show", "default"])
    if out.strip():
        return True
    return default


def _cpu_load_pct() -> int:
    try:
        load1 = os.getloadavg()[0]
        cpus = os.cpu_count() or 1
        pct = int(round((load1 / float(cpus)) * 100.0))
        return max(0, min(100, pct))
    except Exception:
        return 0


def _mem_free_mb() -> int:
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as f:
            for line in f:
                if line.startswith("MemAvailable:"):
                    kb = int(line.split()[1])
                    return int(kb / 1024)
    except Exception:
        pass
    return 0


def _storage_free_mb(path: str) -> int:
    try:
        st = os.statvfs(path)
        return int((st.f_bavail * st.f_frsize) / (1024 * 1024))
    except Exception:
        return 0


def _temp_c() -> int:
    # Raspberry Pi: millidegree Celsius
    for path in (
        "/sys/class/thermal/thermal_zone0/temp",
        "/sys/class/hwmon/hwmon0/temp1_input",
    ):
        try:
            with open(path, "r", encoding="utf-8") as f:
                raw = f.read().strip()
            if not raw:
                continue
            value = float(raw)
            if value > 1000:
                value = value / 1000.0
            return int(round(value))
        except Exception:
            continue
    return 0


def _infer_current_slot_from_local() -> str:
    try:
        parsed = parse_rauc_status(rauc_status_json())
        slot = str(parsed.get("current_slot") or "").strip().upper()
        if slot in {"A", "B"}:
            return slot
    except Exception:
        pass

    # Fallback: parse cmdline root partition (p2=A, p3=B).
    try:
        with open("/proc/cmdline", "r", encoding="utf-8") as f:
            cmdline = f.read().strip().lower()
        if re.search(r"(?:^|/)mmcblk\d+p2(?:\D|$)", cmdline) or re.search(r"partuuid=[0-9a-f-]+-0*2(?:\D|$)", cmdline):
            return "A"
        if re.search(r"(?:^|/)mmcblk\d+p3(?:\D|$)", cmdline) or re.search(r"partuuid=[0-9a-f-]+-0*3(?:\D|$)", cmdline):
            return "B"
    except Exception:
        pass
    return "-"


def _boot_state() -> Dict[str, Any]:
    bootcount = 0
    upgrade_available = False

    # Try common bootcount hints.
    try:
        with open("/proc/cmdline", "r", encoding="utf-8") as f:
            cmdline = f.read()
        m = re.search(r"(?:^|\s)bootcount=(\d+)", cmdline)
        if m:
            bootcount = int(m.group(1))
        m2 = re.search(r"(?:^|\s)upgrade_available=(\d+)", cmdline)
        if m2:
            upgrade_available = m2.group(1) not in ("0", "")
    except Exception:
        pass

    if bootcount == 0:
        for path in ("/data/bootcount", "/run/bootcount"):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    bootcount = int(f.read().strip() or "0")
                break
            except Exception:
                continue

    return {
        "bootcount": bootcount,
        "upgrade_available": bool(upgrade_available),
    }


def _artifact_path(template: str, ota_id: str, device_id: str) -> str:
    text = str(template or "").strip()
    if not text:
        return ""
    try:
        return text.format(ota_id=ota_id, device_id=device_id)
    except Exception:
        return text

def build_event(cfg: Dict[str, Any], ota_id: str, current_version: str, target_version: str,
                phase: str, event: str, error: Dict[str, Any], ota_log: List[str]) -> Dict[str, Any]:
    region = cfg.get("region", {})
    power = cfg.get("power", {})
    network = cfg.get("network", {})
    device_id = str(cfg.get("device_id", "vw-ivi-0026"))
    model = str(cfg.get("device_model", "raspberrypi4"))
    hw_rev = str(cfg.get("device_hw_rev", "1.2"))
    serial = str(cfg.get("device_serial", ""))
    current_slot = str(cfg.get("current_slot", "")).strip() or _infer_current_slot_from_local()
    iface, ip_addr = _network_iface_and_ip()
    gw_ip, gw_iface = _default_gateway_and_iface()
    if gw_iface and iface == "wlan0":
        iface = gw_iface

    battery_pct = _cfg_int(power.get("battery_pct", 0), 0)
    battery_state = str(power.get("battery_state", "UNKNOWN"))
    voltage_mv = _cfg_int(power.get("voltage_mv", 0), 0)
    temp_c = _cfg_int(power.get("temp_c", _temp_c()), _temp_c())

    measured_rssi = _measure_rssi_dbm(iface)
    cfg_rssi = _cfg_int(network.get("rssi_dbm", -55), -55)
    rssi_dbm = measured_rssi if measured_rssi is not None else cfg_rssi

    measured_latency = _measure_latency_ms(gw_ip)
    cfg_latency = _cfg_int(network.get("latency_ms", 373), 373)
    latency_ms = measured_latency if measured_latency is not None else cfg_latency

    gateway_reachable = measured_latency is not None
    if measured_latency is None:
        gateway_reachable = _cfg_bool(network.get("gateway_reachable"), _gateway_reachable(default=True))

    ota_type = str(cfg.get("ota_type", "PARTIAL"))
    attempt = _cfg_int(cfg.get("ota_attempt", 1), 1)

    vehicle_brand = str(cfg.get("vehicle_brand", "Volkswagen"))
    vehicle_series = str(cfg.get("vehicle_series", "ID.5"))
    vehicle_segment = str(cfg.get("vehicle_segment", "C"))
    vehicle_fuel = str(cfg.get("vehicle_fuel", "ICE"))

    context = {
        "region": {
            "country": region.get("country", "DE"),
            "city": region.get("city", "Düsseldorf"),
            "timezone": region.get("timezone", "Europe/Berlin"),
        },
        "time": {
            "local": datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
            "day_of_week": _day_of_week(),
            "time_bucket": _time_bucket(),
        },
        "power": {
            "source": power.get("source", "BATTERY"),
            "battery_pct": battery_pct,
            "battery": {
                "pct": battery_pct,
                "state": battery_state,
                "voltage_mv": voltage_mv,
            },
        },
        "network": {
            "iface": str(network.get("iface", iface)),
            "ip": str(network.get("ip", ip_addr)),
            "rssi_dbm": rssi_dbm,
            "latency_ms": latency_ms,
            "gateway_reachable": gateway_reachable,
        },
        "environment": {
            "temp_c": temp_c,
            "cpu_load_pct": _cpu_load_pct(),
            "mem_free_mb": _mem_free_mb(),
            "storage_free_mb": _storage_free_mb(cfg.get("bundle_dir", "/data/ota")),
        },
        "vehicle_state": {
            "driving": _cfg_bool(cfg.get("vehicle_driving"), False),
            "speed_kph": _cfg_int(cfg.get("vehicle_speed_kph", 0), 0),
        },
    }

    evidence = {
        "ota_log": ota_log,
        "journal_log": _safe_journal("ota-backend.service", lines=50),
        "filesystem": _filesystem_evidence(cfg.get("ota_log_dir", "/data/log/ota")),
        "boot_state": _boot_state(),
    }

    return {
        "ts": _now_ts(),
        "device": {
            "device_id": device_id,
            "model": model,
            "hw_rev": hw_rev,
            "serial": serial,
            "current_slot": current_slot,
        },
        "log_vehicle": {
            "brand": vehicle_brand,
            "series": vehicle_series,
            "segment": vehicle_segment,
            "fuel": vehicle_fuel,
        },
        "ota": {
            "ota_id": ota_id,
            "type": ota_type,
            "current_version": current_version,
            "target_version": target_version,
            "phase": phase,
            "event": event,
            "attempt": attempt,
        },
        "context": context,
        "error": error,
        "evidence": evidence,
        "user_interaction": {
            "user_action": str(cfg.get("user_action", "NONE")),
            "power_event": str(cfg.get("power_event", "NONE")),
        },
        "artifacts": {
            "screenshot_path": _artifact_path(cfg.get("screenshot_path", ""), ota_id, device_id),
            "log_bundle_path": _artifact_path(cfg.get("log_bundle_path", ""), ota_id, device_id),
        },
        "report": {
            "sent": False,
            "sent_at": "",
            "server_response": "",
        },
    }

def _write_event(cfg: Dict[str, Any], ota_id: str, event: Dict[str, Any]) -> None:
    log_dir = os.path.join(cfg.get("ota_log_dir", "/data/log/ota"), ota_id)
    os.makedirs(log_dir, exist_ok=True)
    path = os.path.join(log_dir, "events.jsonl")
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(event) + "\n")

def _queue_event(cfg: Dict[str, Any], event: Dict[str, Any]) -> None:
    queue_path = os.path.join(cfg.get("ota_log_dir", "/data/log/ota"), "queue.jsonl")
    os.makedirs(os.path.dirname(queue_path), exist_ok=True)
    with open(queue_path, "a", encoding="utf-8") as f:
        f.write(json.dumps(event) + "\n")

def _post_event(cfg: Dict[str, Any], event: Dict[str, Any]) -> None:
    url = cfg.get("collector_url") or os.environ.get("COLLECTOR_URL", "")
    event_payload = dict(event or {})

    def _set_report(sent: bool, server_response: str = "") -> None:
        report = dict(event_payload.get("report") or {})
        report["sent"] = bool(sent)
        report["sent_at"] = _now_ts() if sent else str(report.get("sent_at") or "")
        report["server_response"] = str(server_response or "")
        event_payload["report"] = report

    if not url:
        _set_report(False, "collector_url not configured")
        _queue_event(cfg, event_payload)
        return
    try:
        resp = requests.post(url, json=event_payload, timeout=10)
        if resp.status_code >= 300:
            _set_report(False, f"{resp.status_code} {resp.reason}".strip())
            _queue_event(cfg, event_payload)
        else:
            _set_report(True, f"{resp.status_code} {resp.reason}".strip())
    except Exception:
        _set_report(False, "request exception")
        _queue_event(cfg, event_payload)

def _flush_queue(cfg: Dict[str, Any]) -> None:
    queue_path = os.path.join(cfg.get("ota_log_dir", "/data/log/ota"), "queue.jsonl")
    if not os.path.exists(queue_path):
        return
    try:
        with open(queue_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        if not lines:
            return
        os.remove(queue_path)
        for line in lines:
            event = json.loads(line)
            _post_event(cfg, event)
    except Exception:
        return

def start_queue_flusher(cfg: Dict[str, Any], stop_event: threading.Event) -> threading.Thread:
    interval = int(cfg.get("collector_flush_interval_sec", 30))

    def _loop() -> None:
        while not stop_event.is_set():
            _flush_queue(cfg)
            stop_event.wait(interval)

    t = threading.Thread(target=_loop, daemon=True)
    t.start()
    return t

def cleanup_old_bundles(bundle_dir: str, keep: int = 1, preserve: Optional[List[str]] = None) -> int:
    """Remove stale .raucb files to free bundle storage space."""
    removed = 0
    try:
        os.makedirs(bundle_dir, exist_ok=True)
        preserve_abs = {os.path.abspath(p) for p in (preserve or [])}
        candidates = []
        for name in os.listdir(bundle_dir):
            if not name.endswith(".raucb"):
                continue
            path = os.path.abspath(os.path.join(bundle_dir, name))
            if path in preserve_abs:
                continue
            if os.path.isfile(path):
                candidates.append(path)

        candidates.sort(key=lambda p: os.path.getmtime(p), reverse=True)
        keep = max(keep, 0)
        for stale in candidates[keep:]:
            try:
                os.remove(stale)
                removed += 1
            except Exception:
                continue
    except Exception:
        return removed
    return removed


def command_payload_bytes(
    ota_id: str,
    url: str,
    target_version: str,
    expected_sha256: str,
    expected_size: int,
) -> bytes:
    body = {
        "ota_id": str(ota_id or "").strip(),
        "url": str(url or "").strip(),
        "target_version": str(target_version or "").strip(),
        "expected_sha256": str(expected_sha256 or "").strip().lower(),
        "expected_size": int(expected_size or 0),
    }
    return json.dumps(
        body,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")


def sha256sum_file(path: str, chunk_size: int = 1024 * 1024) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(chunk_size)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def verify_bundle_integrity(
    bundle_path: str,
    expected_sha256: str,
    expected_size: Optional[int],
    require_sha256: bool = True,
) -> Tuple[bool, Optional[str], str]:
    try:
        actual_size = int(os.path.getsize(bundle_path))
    except Exception as ex:
        return False, "BUNDLE_STAT_FAILED", f"cannot stat bundle: {ex.__class__.__name__}"

    expected_size_int = 0
    try:
        expected_size_int = int(expected_size or 0)
    except Exception:
        expected_size_int = 0

    if expected_size_int > 0 and actual_size != expected_size_int:
        return False, "SIZE_MISMATCH", f"size mismatch expected={expected_size_int} actual={actual_size}"

    expected_hash = str(expected_sha256 or "").strip().lower()
    if require_sha256 and not expected_hash:
        return False, "SHA256_REQUIRED", "expected_sha256 is required by policy"

    if expected_hash:
        try:
            actual_hash = sha256sum_file(bundle_path)
        except Exception as ex:
            return False, "HASH_COMPUTE_FAILED", f"sha256 computation failed: {ex.__class__.__name__}"
        if actual_hash.lower() != expected_hash:
            return (
                False,
                "HASH_MISMATCH",
                f"sha256 mismatch expected={expected_hash[:16]} actual={actual_hash[:16]}",
            )

    return True, None, "bundle integrity verified"


def _verify_ed25519_signature(payload: bytes, sig_b64: str, pubkey_path: str) -> Tuple[bool, str]:
    msg_fd = -1
    sig_fd = -1
    msg_path = ""
    sig_path = ""
    try:
        sig_bytes = base64.b64decode(str(sig_b64 or "").encode("ascii"), validate=True)
    except Exception:
        return False, "invalid base64 signature"

    if not os.path.exists(pubkey_path):
        return False, f"public key missing: {pubkey_path}"

    try:
        msg_fd, msg_path = tempfile.mkstemp(prefix="ota-cmd-", suffix=".msg")
        sig_fd, sig_path = tempfile.mkstemp(prefix="ota-cmd-", suffix=".sig")
        os.write(msg_fd, payload)
        os.write(sig_fd, sig_bytes)
        os.close(msg_fd)
        os.close(sig_fd)
        msg_fd = -1
        sig_fd = -1

        proc = subprocess.run(
            [
                "openssl",
                "pkeyutl",
                "-verify",
                "-pubin",
                "-inkey",
                pubkey_path,
                "-rawin",
                "-in",
                msg_path,
                "-sigfile",
                sig_path,
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if proc.returncode != 0:
            detail = (proc.stderr or proc.stdout or "").strip()
            return False, detail or f"openssl rc={proc.returncode}"
        return True, ""
    except Exception as ex:
        return False, f"signature verification error: {ex.__class__.__name__}: {ex}"
    finally:
        if msg_fd >= 0:
            try:
                os.close(msg_fd)
            except Exception:
                pass
        if sig_fd >= 0:
            try:
                os.close(sig_fd)
            except Exception:
                pass
        for p in (msg_path, sig_path):
            if p and os.path.exists(p):
                try:
                    os.remove(p)
                except Exception:
                    pass


def verify_command_signature(
    cfg: Dict[str, Any],
    ota_id: str,
    url: str,
    target_version: str,
    expected_sha256: str,
    expected_size: Optional[int],
    signature: Optional[Dict[str, Any]],
) -> Tuple[bool, Optional[str], str]:
    required = _cfg_bool(cfg.get("require_command_signature"), True)
    if not signature:
        if required:
            return False, "SIGNATURE_REQUIRED", "signature field is required by policy"
        return True, None, "signature skipped"

    if not isinstance(signature, dict):
        return False, "SIGNATURE_INVALID", "signature field must be object"

    algorithm = str(signature.get("algorithm") or "").strip().lower()
    key_id = str(signature.get("key_id") or "").strip()
    sig_value = str(signature.get("value") or "").strip()

    if algorithm != "ed25519":
        return False, "SIGNATURE_ALGO", f"unsupported signature algorithm: {algorithm or 'empty'}"
    if not sig_value:
        return False, "SIGNATURE_INVALID", "signature.value is empty"

    expected_key_id = str(cfg.get("expected_signature_key_id") or "").strip()
    if expected_key_id and key_id and key_id != expected_key_id:
        return (
            False,
            "SIGNATURE_KEY_ID",
            f"key_id mismatch expected={expected_key_id} got={key_id}",
        )

    pubkey_path = str(cfg.get("signature_public_key_path") or "/etc/ota-backend/keys/ota-signing.pub").strip()
    payload = command_payload_bytes(
        ota_id=ota_id,
        url=url,
        target_version=target_version,
        expected_sha256=expected_sha256,
        expected_size=int(expected_size or 0),
    )
    ok, detail = _verify_ed25519_signature(payload, sig_value, pubkey_path)
    if not ok:
        return False, "SIGNATURE_VERIFY_FAILED", detail
    return True, None, "signature verified"


def _target_slot_device(cfg: Dict[str, Any]) -> Tuple[Optional[str], Optional[str]]:
    parsed = parse_rauc_status(rauc_status_json())
    current = str(parsed.get("current_slot") or "").strip().upper()
    if current == "A":
        target_slot = "B"
    elif current == "B":
        target_slot = "A"
    else:
        return None, None

    slot_a_dev = str(cfg.get("rootfs_slot_a_dev") or "/dev/mmcblk0p2").strip()
    slot_b_dev = str(cfg.get("rootfs_slot_b_dev") or "/dev/mmcblk0p3").strip()
    target_dev = slot_b_dev if target_slot == "B" else slot_a_dev
    return target_slot, target_dev


def post_write_verify(cfg: Dict[str, Any], on_log) -> Tuple[bool, Optional[str], str]:
    enabled = _cfg_bool(cfg.get("post_write_verify_enabled"), True)
    if not enabled:
        return True, None, "post-write verification disabled"

    target_slot, target_dev = _target_slot_device(cfg)
    if not target_slot or not target_dev:
        return False, "POST_WRITE_SLOT_UNKNOWN", "cannot infer target slot/device for post-write verify"

    timeout_sec = _cfg_int(cfg.get("post_write_verify_timeout_sec", 120), 120)
    on_log(f"POST_WRITE VERIFY START slot={target_slot} dev={target_dev}")

    try:
        subprocess.run(["sync"], check=False)
    except Exception:
        pass

    try:
        proc = subprocess.run(
            ["e2fsck", "-pf", target_dev],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=max(10, timeout_sec),
        )
    except FileNotFoundError:
        return False, "POST_WRITE_TOOL_MISSING", "e2fsck not found"
    except subprocess.TimeoutExpired:
        return False, "POST_WRITE_TIMEOUT", f"e2fsck timed out after {timeout_sec}s"
    except Exception as ex:
        return False, "POST_WRITE_ERROR", f"e2fsck exception: {ex.__class__.__name__}"

    if proc.returncode not in (0, 1):
        detail = (proc.stderr or proc.stdout or "").strip()
        return False, "POST_WRITE_FAILED", detail or f"e2fsck rc={proc.returncode}"

    return True, None, f"post-write verified slot={target_slot} dev={target_dev}"

def download_with_retries(url: str, dest: str, retries: int, timeout: int,
                          on_log):
    last_status = None
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    partial = f"{dest}.part"

    for attempt in range(1, retries + 1):
        for old in (dest, partial):
            try:
                if os.path.exists(old):
                    os.remove(old)
            except Exception:
                pass
        try:
            with requests.get(url, stream=True, timeout=timeout) as resp:
                last_status = resp.status_code
                if resp.status_code >= 500:
                    on_log(f"DOWNLOAD FAIL code=HTTP_5XX http={resp.status_code} attempt={attempt}")
                    if attempt == retries:
                        return "HTTP_5XX", last_status
                    time.sleep(2 * attempt)
                    continue
                resp.raise_for_status()
                with open(partial, "wb") as f:
                    for chunk in resp.iter_content(chunk_size=1024 * 1024):
                        if chunk:
                            f.write(chunk)
            os.replace(partial, dest)
            on_log("DOWNLOAD OK")
            return None, last_status
        except requests.RequestException as ex:
            try:
                if os.path.exists(partial):
                    os.remove(partial)
            except Exception:
                pass
            on_log(f"DOWNLOAD FAIL error={ex.__class__.__name__} attempt={attempt}")
            if attempt == retries:
                last_status = getattr(ex.response, "status_code", None)
                return ("HTTP_5XX" if (last_status or 0) >= 500 else "HTTP_ERROR"), last_status
            time.sleep(2 * attempt)
        except OSError as ex:
            try:
                if os.path.exists(partial):
                    os.remove(partial)
            except Exception:
                pass
            code = "NO_SPACE" if ex.errno == errno.ENOSPC else "IO_ERROR"
            on_log(f"DOWNLOAD FAIL code={code} attempt={attempt}")
            # ENOSPC does not recover by retrying immediately.
            if code == "NO_SPACE" or attempt == retries:
                return code, last_status
            time.sleep(2 * attempt)
    return "HTTP_ERROR", last_status

def rauc_status_json(timeout_sec: float = 1.5) -> Dict[str, Any]:
    try:
        out = subprocess.check_output(
            ["rauc", "status", "--output-format=json"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=timeout_sec,
        )
        parsed = json.loads(out)
        return parsed if isinstance(parsed, dict) else {}
    except Exception:
        return {}


def _iter_slot_items(raw_slots: Any) -> Iterable[Tuple[str, Dict[str, Any]]]:
    """RAUC slot output can be either dict or list-of-dicts depending on version."""
    if isinstance(raw_slots, dict):
        for name, info in raw_slots.items():
            if isinstance(name, str) and isinstance(info, dict):
                yield name, info
        return

    if isinstance(raw_slots, list):
        for entry in raw_slots:
            if not isinstance(entry, dict):
                continue
            for name, info in entry.items():
                if isinstance(name, str) and isinstance(info, dict):
                    yield name, info


def parse_rauc_status(status: Dict[str, Any]) -> Dict[str, Any]:
    """Normalize RAUC status JSON into a stable shape used by the API/UI."""
    if not isinstance(status, dict):
        status = {}

    rootfs_slots: List[Dict[str, Any]] = []
    by_name: Dict[str, Dict[str, Any]] = {}

    for name, info in _iter_slot_items(status.get("slots", {})):
        slot_class = str(info.get("class") or "")
        state_val = info.get("state")
        slot = {
            "name": name,
            "state": str(state_val) if state_val else "unknown",
            "bootname": info.get("bootname"),
            "device": info.get("device"),
        }
        by_name[name] = slot

        # UI expects A/B rootfs view; hide boot.* helper slots from status panel.
        if name.startswith("rootfs.") or slot_class == "rootfs":
            rootfs_slots.append(slot)

    booted = status.get("booted")
    current_slot: Optional[str] = None

    if isinstance(booted, str) and booted:
        # Usually booted is slot name (e.g. rootfs.0); convert to bootname (A/B) if available.
        current_slot = by_name.get(booted, {}).get("bootname") or booted
    elif isinstance(booted, dict):
        bootname = booted.get("bootname")
        slot_name = booted.get("slot") or booted.get("name")
        if isinstance(bootname, str) and bootname:
            current_slot = bootname
        elif isinstance(slot_name, str) and slot_name:
            current_slot = by_name.get(slot_name, {}).get("bootname") or slot_name

    if not current_slot:
        # Fallback: infer from slot state marker
        for slot in rootfs_slots:
            if slot.get("state") == "booted":
                current_slot = slot.get("bootname") or slot.get("name")
                break

    return {
        "compatible": status.get("compatible"),
        "current_slot": current_slot,
        "slots": rootfs_slots,
    }

def rauc_install(bundle_path: str) -> int:
    try:
        return subprocess.call(["rauc", "install", bundle_path])
    except Exception:
        return 1

def rauc_mark_good() -> int:
    try:
        return subprocess.call(["rauc", "status", "mark-good"])
    except Exception:
        return 1
