FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://wifi-autoconnect.config"

SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install:append() {
    install -d ${D}/var/lib/connman
    install -m 0644 ${WORKDIR}/wifi-autoconnect.config ${D}/var/lib/connman/wifi_auto.config
}
