SUMMARY = "Autoload i2c-dev kernel module"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://i2c-dev.conf"

S = "${WORKDIR}"

do_install() {
    install -d ${D}${sysconfdir}/modules-load.d
    install -m 0644 ${WORKDIR}/i2c-dev.conf ${D}${sysconfdir}/modules-load.d/i2c-dev.conf
}

FILES:${PN} = "${sysconfdir}/modules-load.d/i2c-dev.conf"
