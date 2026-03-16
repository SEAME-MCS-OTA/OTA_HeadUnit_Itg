from app.ota_logic import parse_rauc_status


def test_parse_rauc_status_list_slots_and_string_booted():
    raw = {
        "compatible": "ivi-hu-rpi4",
        "booted": "rootfs.1",
        "slots": [
            {"rootfs.0": {"state": "inactive", "bootname": "A", "device": "/dev/mmcblk0p2"}},
            {"rootfs.1": {"state": "booted", "bootname": "B", "device": "/dev/mmcblk0p3"}},
        ],
    }

    parsed = parse_rauc_status(raw)
    assert parsed["compatible"] == "ivi-hu-rpi4"
    assert parsed["current_slot"] == "B"
    assert len(parsed["slots"]) == 2


def test_parse_rauc_status_dict_slots_and_dict_booted():
    raw = {
        "compatible": "ivi-hu-rpi4",
        "booted": {"slot": "rootfs.0"},
        "slots": {
            "rootfs.0": {"state": "booted", "bootname": "A", "device": "/dev/mmcblk0p2"},
            "rootfs.1": {"state": "inactive", "bootname": "B", "device": "/dev/mmcblk0p3"},
        },
    }

    parsed = parse_rauc_status(raw)
    assert parsed["compatible"] == "ivi-hu-rpi4"
    assert parsed["current_slot"] == "A"
    assert len(parsed["slots"]) == 2


def test_parse_rauc_status_empty():
    parsed = parse_rauc_status({})
    assert parsed["compatible"] is None
    assert parsed["current_slot"] is None
    assert parsed["slots"] == []
