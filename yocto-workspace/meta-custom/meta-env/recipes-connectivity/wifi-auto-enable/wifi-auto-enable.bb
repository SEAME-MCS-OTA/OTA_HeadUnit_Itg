SUMMARY = "WiFi auto-enable service for ConnMan"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://wifi-enable.sh \
           file://wifi-auto-enable.service \
"

inherit systemd

SYSTEMD_SERVICE:${PN} = "wifi-auto-enable.service"
SYSTEMD_AUTO_ENABLE = "enable"

RDEPENDS:${PN} = "connman"

do_install() {
    # Install script
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/wifi-enable.sh ${D}${bindir}/

    # Install systemd service
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/wifi-auto-enable.service ${D}${systemd_system_unitdir}/
}

FILES:${PN} = "${bindir}/wifi-enable.sh"
