import os
import json
import logging
import threading
import time
import subprocess
import re
import glob
from datetime import datetime
from typing import Dict, Any, Optional, Callable, Tuple
from flask import Flask, jsonify, request

from .ota_logic import (
    build_event,                    # OTA 이벤트 Json 객체 생성 함수 (phase/event/error/디바이스/전원/네트워크/로그)
    _write_event,                   # OTA 이벤트 파일에 기록 함수 (data/log/ota/{ota_id}/events.jsonl)
    _post_event,                    # OTA 이벤트를 collector_url(서버)로 HTTP POST 전송 함수

    verify_command_signature,       # signature 검증

    cleanup_old_bundles,            # 오래된 OTA 번들 파일 정리 함수
    download_with_retries,          # OTA 번들 다운로드 함수 (URL에서 파일 다운로드 + 재시도)
    verify_bundle_integrity,        # 다운로드된 OTA 번들의 무결성 검증 함수 (SHA256/크기 검증)
    
    rauc_install,                   # RAUC 설치 명령 실행 함수 (RAUC로 OTA 번들 설치 시도)
    post_write_verify,              # RAUC 설치 후 검증 함수 (설치된 슬롯의 상태/버전 확인)
    rauc_mark_good,

    rauc_status_json,               # RAUC status를 호출하여 JSON으로 파싱하는 함수
    parse_rauc_status,              # RAUC status JSON에서 호환성/현재 슬롯/슬롯 목록을 추출하는 함수
    load_config,                    # config 파일 로드 함수
    start_queue_flusher,
    _cfg_bool,                      # 설정값을 bool로 해석하는 헬퍼 함수
    _cfg_int,                       # 설정값을 int로 해석하는 헬퍼 함수
    
    state,                          # OTA 상태 저장 객체

    PHASE_DOWNLOAD, PHASE_APPLY, PHASE_REBOOT, PHASE_COMMIT,
    EVENT_START, EVENT_OK, EVENT_FAIL,
)

from .mqtt_utils import MQTTCommandBridge,_ota_start_lock

from .IP_helpers import _get_ip_and_source


ACTIVE_PHASES = (PHASE_DOWNLOAD, PHASE_APPLY, PHASE_REBOOT, PHASE_COMMIT)

app = Flask(__name__)
logging.basicConfig(
    level=getattr(logging, os.environ.get("LOG_LEVEL", "INFO").upper(), logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)


# --- Runtime request logging / HTTP middleware ---
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


# --- RAUC 정보가 비어있거나 불완전할 때 슬롯/버전을 보정 추론 ---
def _slot_from_hint(raw: str) -> Optional[str]:     # 문자열 힌트로 현재 슬롯 A/B 추론 (예: "A", "slot-a", "rootfs.0", "/dev/mmcblk0p2", "PARTUUID=xxx-02" 등)
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


def _infer_current_slot() -> tuple[Optional[str], str]:     # /run/rauc/* -> /proc/cmdline -> /proc/mounts 순서대로 현재 슬롯 A/B 추론
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


def _is_unknown_version(raw: Any) -> bool:      # "unknown", "none", "n/a", "-" 등의 버전 문자열을 현재 버전 정보가 없는 것으로 간주
    s = str(raw or "").strip().lower()
    return s in ("", "-", "unknown", "none", "n/a")


def _infer_current_version_from_ota_logs(log_root: str) -> Optional[str]:   # OTA 이벤트 로그 파일을 역순으로 탐색하여 현재 버전 정보 추론
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

CFG_PATH = os.environ.get("OTA_BACKEND_CONFIG", "/etc/ota-backend/config.json")
CFG: Dict[str, Any] = load_config(CFG_PATH)
MQTT_BRIDGE: Optional[MQTTCommandBridge] = None

_stop_event = threading.Event()
start_queue_flusher(CFG, _stop_event)
_mqtt_heartbeat_started = False


# --- HTTP APIs ---
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


@app.post("/ota/reboot")
def ota_reboot():
    os.system("systemctl reboot")
    return jsonify({"ok": True})


# --- mqtt status/progress 메시지 발행 함수 ---
def _publish_mqtt_status(status: str, target_version: str, message: str = "") -> None:
    if MQTT_BRIDGE:
        MQTT_BRIDGE.publish_status(status, target_version, message)


def _publish_mqtt_progress(target_version: str, progress: int, message: str = "") -> None:
    if MQTT_BRIDGE:
        MQTT_BRIDGE.publish_progress(target_version, progress, message)

#########  핵심!!! ###################################
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

        def _emit_event(phase: str, event_name: str, error: Optional[Dict[str, Any]] = None) -> None:
            event = build_event(
                CFG,
                ota_id,
                state.current_version,
                target_version,
                phase,
                event_name,
                error or {},
                ota_log,
            )
            _write_event(CFG, ota_id, event)
            _post_event(CFG, event)

        def _fail(
            phase: str,
            code: str,
            message: str,
            mqtt_message: Optional[str] = None,
            retryable: bool = False,
            log_line: str = "",
        ) -> None:
            state.event = EVENT_FAIL
            state.last_error = code
            if log_line:
                _log(log_line)
            _emit_event(
                phase,
                EVENT_FAIL,
                {"code": code, "message": message, "retryable": retryable},
            )
            _publish_mqtt_status("failed", target_version, mqtt_message or message)
            state.phase = None

        try:
            # 1) Initialize OTA runtime state.
            state.active_ota_id = ota_id
            state.target_version = target_version
            state.last_error = None

            # 2) DOWNLOAD phase start.
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
            _emit_event(PHASE_DOWNLOAD, EVENT_START)

            # 3) Verify signed command policy before download.
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
                code = sig_code or "SIGNATURE_VERIFY_FAILED"
                _fail(
                    PHASE_DOWNLOAD,
                    code,
                    sig_msg,
                    mqtt_message=f"Signature verify failed: {sig_msg}",
                    log_line=f"SIGNATURE FAIL code={code} detail={sig_msg}",
                )
                return
            if sig_msg:
                _log(f"SIGNATURE OK {sig_msg}")

            # 4) Download bundle (with extra NO_SPACE retry path).
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
                if err_code == "HTTP_5XX":
                    msg = f"Server error: {last_status} Service Unavailable" if last_status else "Server error: 5xx"
                elif err_code == "NO_SPACE":
                    msg = "No space left on bundle storage"
                elif err_code == "IO_ERROR":
                    msg = "Storage I/O error during download"
                else:
                    msg = "Download error"
                _fail(
                    PHASE_DOWNLOAD,
                    err_code,
                    msg,
                    mqtt_message=msg,
                    retryable=err_code == "HTTP_5XX",
                )
                return

            # 5) Verify downloaded bundle integrity.
            verify_ok, verify_code, verify_msg = verify_bundle_integrity(
                bundle_path=bundle_path,
                expected_sha256=expected_sha256,
                expected_size=normalized_expected_size,
                require_sha256=_cfg_bool(CFG.get("require_sha256"), True),
            )
            if not verify_ok:
                code = verify_code or "VERIFY_FAILED"
                _fail(
                    PHASE_DOWNLOAD,
                    code,
                    verify_msg,
                    mqtt_message=verify_msg,
                    log_line=f"VERIFY FAIL code={code} detail={verify_msg}",
                )
                return
            _log("VERIFY OK")

            # 6) APPLY phase start.
            _publish_mqtt_progress(target_version, 40, "Download complete")
            state.phase = PHASE_APPLY
            state.event = EVENT_START
            _log("APPLY START")
            _publish_mqtt_status("installing", target_version, "APPLY START")
            _publish_mqtt_progress(target_version, 70, "Applying bundle")
            _emit_event(PHASE_APPLY, EVENT_START)

            rc = rauc_install(bundle_path)
            if rc != 0:
                _fail(PHASE_APPLY, "RAUC_INSTALL", "RAUC install failed")
                return

            # 7) Optional post-write verification.
            post_ok, post_code, post_msg = post_write_verify(CFG, _log)
            if not post_ok:
                code = post_code or "POST_WRITE_FAILED"
                _fail(
                    PHASE_APPLY,
                    code,
                    post_msg,
                    mqtt_message=f"Post-write verify failed: {post_msg}",
                    log_line=f"POST_WRITE FAIL code={code} detail={post_msg}",
                )
                return
            _log("POST_WRITE OK")

            # 8) APPLY completed.
            state.phase = PHASE_REBOOT
            state.event = EVENT_OK
            state.current_version = target_version
            _log("APPLY OK")
            _publish_mqtt_progress(target_version, 90, "Apply complete")
            _emit_event(PHASE_REBOOT, EVENT_OK)

            # 9) Default path: reboot immediately after apply.
            if bool(CFG.get("reboot_after_apply", False)):
                _publish_mqtt_status("completed", target_version, "APPLY OK, rebooting")
                _publish_mqtt_progress(target_version, 100, "Completed")
                os.system("systemctl reboot")
                return

            # 10) Non-reboot policy: explicit commit.
            state.phase = PHASE_COMMIT
            state.event = EVENT_START
            _log("COMMIT START")
            _publish_mqtt_status("installing", target_version, "COMMIT START")
            _emit_event(PHASE_COMMIT, EVENT_START)

            if bool(CFG.get("mark_good_on_commit", True)):
                rauc_mark_good()

            state.event = EVENT_OK
            _log("COMMIT OK")
            _publish_mqtt_status("completed", target_version, "COMMIT OK")
            _publish_mqtt_progress(target_version, 100, "Completed")
            _emit_event(PHASE_COMMIT, EVENT_OK)
            state.phase = None
        except Exception as ex:
            state.event = EVENT_FAIL
            state.last_error = "INTERNAL"
            _log(f"INTERNAL ERROR {ex.__class__.__name__}")
            _emit_event(
                state.phase or "UNKNOWN",
                EVENT_FAIL,
                {"code": "INTERNAL", "message": str(ex), "retryable": False},
            )
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
#####################################################

# --- Process bootstrap ---
def _init_mqtt_bridge() -> None:
    global MQTT_BRIDGE
    if MQTT_BRIDGE is None:
        MQTT_BRIDGE = MQTTCommandBridge(CFG, _start_ota_job, _append_runtime_log)
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
