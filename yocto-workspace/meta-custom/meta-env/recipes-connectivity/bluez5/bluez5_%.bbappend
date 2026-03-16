FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://main.conf \
            file://experimental.conf \
"

inherit systemd

do_install:append() {
    install -d ${D}${sysconfdir}/bluetooth
    install -m 0644 ${WORKDIR}/main.conf ${D}${sysconfdir}/bluetooth/main.conf

    # Install systemd drop-in for experimental flag
    install -d ${D}${systemd_system_unitdir}/bluetooth.service.d
    install -m 0644 ${WORKDIR}/experimental.conf ${D}${systemd_system_unitdir}/bluetooth.service.d/experimental.conf
}

FILES:${PN} += "${sysconfdir}/bluetooth/main.conf \
                ${systemd_system_unitdir}/bluetooth.service.d/experimental.conf \
"
