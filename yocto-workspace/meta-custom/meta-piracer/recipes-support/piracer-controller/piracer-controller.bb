SUMMARY = "PiRacer controller service for hardware input"
LICENSE = "CLOSED"

SRC_URI = "\
    file://controller.py \
    file://gamepads.py \
    file://piracer-controller.service \
"

S = "${WORKDIR}"

inherit allarch systemd

do_install() {
    install -d ${D}${libdir}/piracer-controller
    install -m 0644 ${WORKDIR}/controller.py ${D}${libdir}/piracer-controller/controller.py
    install -m 0644 ${WORKDIR}/gamepads.py ${D}${libdir}/piracer-controller/gamepads.py

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/piracer-controller.service ${D}${systemd_system_unitdir}/piracer-controller.service
}

FILES:${PN} = "\
    ${libdir}/piracer-controller \
    ${systemd_system_unitdir}/piracer-controller.service \
"

SYSTEMD_SERVICE:${PN} = "piracer-controller.service"
SYSTEMD_AUTO_ENABLE = "enable"

RDEPENDS:${PN} += "\
    python3-core \
    python3-multiprocessing \
    python3-logging \
    python3-fcntl \
    des-piracer-vehicles \
"
