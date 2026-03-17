from app.ota_logic import build_event


def test_build_event_contains_extended_schema():
    cfg = {
        "device_id": "vw-ivi-0012",
        "device_model": "raspberrypi4",
        "device_hw_rev": "1.2",
        "device_serial": "RPI4-3806",
        "ota_type": "PARTIAL",
        "ota_attempt": 1,
        "vehicle_brand": "Volkswagen",
        "vehicle_series": "Golf",
        "vehicle_segment": "C",
        "vehicle_fuel": "ICE",
        "region": {"country": "DE", "city": "Munich", "timezone": "Europe/Berlin"},
        "power": {"source": "AC", "battery_pct": 67, "battery_state": "CHARGING", "voltage_mv": 4917},
        "network": {"iface": "wlan0", "rssi_dbm": -65, "latency_ms": 159, "gateway_reachable": True},
        "ota_log_dir": "/tmp",
        "bundle_dir": "/tmp",
    }

    event = build_event(
        cfg=cfg,
        ota_id="ota-20260105-0f9303",
        current_version="1.2.3",
        target_version="1.2.4",
        phase="VERIFY",
        event="FAIL",
        error={"code": "HASH_MISMATCH", "message": "SHA256 mismatch", "retryable": False},
        ota_log=["VERIFY START", "VERIFY FAIL code=HASH_MISMATCH"],
    )

    assert "ts" in event
    assert "device" in event and isinstance(event["device"], dict)
    assert "log_vehicle" in event and isinstance(event["log_vehicle"], dict)
    assert "ota" in event and isinstance(event["ota"], dict)
    assert "context" in event and isinstance(event["context"], dict)
    assert "error" in event and isinstance(event["error"], dict)
    assert "evidence" in event and isinstance(event["evidence"], dict)
    assert "user_interaction" in event and isinstance(event["user_interaction"], dict)
    assert "artifacts" in event and isinstance(event["artifacts"], dict)
    assert "report" in event and isinstance(event["report"], dict)

    assert event["device"]["device_id"] == "vw-ivi-0012"
    assert event["ota"]["ota_id"] == "ota-20260105-0f9303"
    assert event["ota"]["attempt"] == 1
    assert "boot_state" in event["evidence"]
    assert "battery" in event["context"]["power"]
    assert "ip" in event["context"]["network"]
