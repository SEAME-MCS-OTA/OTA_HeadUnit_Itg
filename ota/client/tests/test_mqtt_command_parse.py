from app.mqtt_utils import parse_mqtt_update_command


def test_parse_ota_gh_style_payload():
    payload = {
        "command": "update",
        "ota_id": "ota-20260224-0001",
        "firmware": {
            "version": "1.2.8",
            "url": "http://192.168.86.29:18081/my-hu-bundle-raspberrypi4-64.raucb",
        },
    }

    parsed = parse_mqtt_update_command(payload)

    assert parsed == {
        "ota_id": "ota-20260224-0001",
        "url": "http://192.168.86.29:18081/my-hu-bundle-raspberrypi4-64.raucb",
        "target_version": "1.2.8",
    }


def test_parse_direct_payload():
    payload = {
        "ota_id": "ota-direct-1",
        "url": "http://server/bundle.raucb",
        "target_version": "2.0.0",
    }

    parsed = parse_mqtt_update_command(payload)

    assert parsed == {
        "ota_id": "ota-direct-1",
        "url": "http://server/bundle.raucb",
        "target_version": "2.0.0",
    }


def test_parse_rejects_non_update_command():
    payload = {
        "command": "ping",
        "firmware": {"version": "1.2.8", "url": "http://server/bundle.raucb"},
    }

    assert parse_mqtt_update_command(payload) is None


def test_parse_generates_ota_id_when_missing():
    payload = {
        "command": "update",
        "firmware": {"version": "1.2.8", "url": "http://server/bundle.raucb"},
    }

    parsed = parse_mqtt_update_command(payload, default_ota_id_prefix="demo")

    assert parsed is not None
    assert parsed["ota_id"].startswith("demo-")
    assert parsed["target_version"] == "1.2.8"


def test_parse_includes_integrity_and_signature_fields():
    payload = {
        "command": "update",
        "ota_id": "ota-signed-1",
        "firmware": {
            "version": "2.0.0",
            "url": "http://server/bundle.raucb",
            "sha256": "a" * 64,
            "size": 123456,
            "signature": {
                "algorithm": "ed25519",
                "key_id": "ota-ed25519-v1",
                "value": "ZmFrZS1zaWduYXR1cmU=",
            },
        },
    }

    parsed = parse_mqtt_update_command(payload)
    assert parsed is not None
    assert parsed["expected_sha256"] == "a" * 64
    assert parsed["expected_size"] == 123456
    assert parsed["signature"]["algorithm"] == "ed25519"
