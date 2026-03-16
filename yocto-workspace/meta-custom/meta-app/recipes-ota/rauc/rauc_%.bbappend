FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://system.conf \
    file://ca.cert.pem \
    file://rauc-slot-switch.sh \
    file://rauc-bootloader-backend.sh \
    file://rauc-boot-check.sh \
    file://rauc-mark-good.sh \
    file://rauc-boot-check.service \
    file://rauc-mark-good.service \
"

inherit systemd

SYSTEMD_SERVICE:${PN} += "rauc-boot-check.service rauc-mark-good.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"
# Use project-specific RAUC config shipped in ${PN}; avoid pulling separate virtual-rauc-conf.
RRECOMMENDS:${PN}:remove = "virtual-rauc-conf"
RAUC_PROJECT_CERT ?= "${TOPDIR}/../../ota/keys/rauc/rauc.cert.pem"

do_install:append() {
    # Override RAUC config/keyring with project files
    install -d ${D}${sysconfdir}/rauc
    install -m 0644 ${WORKDIR}/system.conf ${D}${sysconfdir}/rauc/system.conf
    if [ -f "${RAUC_PROJECT_CERT}" ]; then
        install -m 0644 "${RAUC_PROJECT_CERT}" ${D}${sysconfdir}/rauc/ca.cert.pem
    else
        install -m 0644 ${WORKDIR}/ca.cert.pem ${D}${sysconfdir}/rauc/ca.cert.pem
    fi

    # Slot-switch scripts
    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/rauc-slot-switch.sh ${D}${sbindir}/rauc-slot-switch.sh
    install -m 0755 ${WORKDIR}/rauc-bootloader-backend.sh ${D}${sbindir}/rauc-bootloader-backend.sh
    install -m 0755 ${WORKDIR}/rauc-boot-check.sh  ${D}${sbindir}/rauc-boot-check.sh
    install -m 0755 ${WORKDIR}/rauc-mark-good.sh   ${D}${sbindir}/rauc-mark-good.sh

    # Systemd service units
    install -d ${D}${systemd_unitdir}/system
    install -m 0644 ${WORKDIR}/rauc-boot-check.service \
        ${D}${systemd_unitdir}/system/rauc-boot-check.service
    install -m 0644 ${WORKDIR}/rauc-mark-good.service \
        ${D}${systemd_unitdir}/system/rauc-mark-good.service

    # Enable rauc-boot-check under sysinit.target (early boot)
    install -d ${D}${systemd_unitdir}/system/sysinit.target.wants
    ln -sf ../rauc-boot-check.service \
        ${D}${systemd_unitdir}/system/sysinit.target.wants/rauc-boot-check.service

    # Enable rauc-mark-good under multi-user.target
    install -d ${D}${systemd_unitdir}/system/multi-user.target.wants
    ln -sf ../rauc-mark-good.service \
        ${D}${systemd_unitdir}/system/multi-user.target.wants/rauc-mark-good.service
}

FILES:${PN} += " \
    ${sysconfdir}/rauc/system.conf \
    ${sysconfdir}/rauc/ca.cert.pem \
    ${sbindir}/rauc-slot-switch.sh \
    ${sbindir}/rauc-bootloader-backend.sh \
    ${sbindir}/rauc-boot-check.sh \
    ${sbindir}/rauc-mark-good.sh \
    ${systemd_unitdir}/system/rauc-boot-check.service \
    ${systemd_unitdir}/system/rauc-mark-good.service \
    ${systemd_unitdir}/system/sysinit.target.wants/rauc-boot-check.service \
    ${systemd_unitdir}/system/multi-user.target.wants/rauc-mark-good.service \
"
