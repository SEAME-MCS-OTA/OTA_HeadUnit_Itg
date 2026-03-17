SUMMARY = "Bluetooth Audio ALSA Backend"
DESCRIPTION = "BlueALSA is a Linux Bluetooth stack (BlueZ) integration with ALSA"
HOMEPAGE = "https://github.com/Arkq/bluez-alsa"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=143bc4e73f39cc5e89d6e096ac0315ba"

DEPENDS = "alsa-lib bluez5 dbus glib-2.0 glib-2.0-native sbc"

SRC_URI = "git://github.com/Arkq/bluez-alsa.git;protocol=https;branch=master \
           file://bluealsa.service \
           file://bluealsa-aplay.service \
"

SRCREV = "v4.3.1"
PV = "4.3.1+git${SRCPV}"

S = "${WORKDIR}/git"

inherit autotools pkgconfig systemd

PACKAGECONFIG ??= "cli aplay"
PACKAGECONFIG[aac] = "--enable-aac,--disable-aac,fdk-aac"
PACKAGECONFIG[cli] = "--enable-cli,--disable-cli"
PACKAGECONFIG[aplay] = "--enable-aplay,--disable-aplay"

SYSTEMD_SERVICE:${PN} = "bluealsa.service bluealsa-aplay.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install:append() {
    # Install systemd services
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/bluealsa.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${WORKDIR}/bluealsa-aplay.service ${D}${systemd_system_unitdir}/

    # Create bluealsa user directory for runtime
    install -d ${D}/var/lib/bluealsa
}

FILES:${PN} += "${systemd_system_unitdir}/bluealsa.service \
                ${systemd_system_unitdir}/bluealsa-aplay.service \
                /var/lib/bluealsa \
                ${datadir}/dbus-1/system.d/bluealsa.conf \
                ${libdir}/alsa-lib/*.so \
"

FILES:${PN}-staticdev += "${libdir}/alsa-lib/*.a"

RDEPENDS:${PN} = "bluez5 alsa-lib sbc"
