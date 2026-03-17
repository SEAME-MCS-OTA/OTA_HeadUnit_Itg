SUMMARY = "Qt 6 modular head unit application"
LICENSE = "CLOSED"
PV = "1.0.1"

SRC_URI = "file://headunit.service \
           file://rfkill-unblock.service \
           file://headunit-bluetooth.conf \
"
# bluetooth-class-fix.service 임시 비활성화 - 테스트 후 활성화

S = "${WORKDIR}/HeadUnit"

inherit qt6-cmake systemd

HEADUNIT_SRC ?= "${TOPDIR}/../../Head-Unit"

DEPENDS = "\
    qtbase \
    qtdeclarative \
    qtdeclarative-native \
    qtmultimedia \
    qtwayland \
    qtwayland-native \
    qtshadertools-native \
    qtconnectivity \
    qtlocation \
    qtpositioning \
    qt5compat \
    bluez5 \
    pulseaudio \
    wayland \
"

RDEPENDS:${PN} = "\
    qtbase \
    qtwayland \
    qtdeclarative-plugins \
    qtdeclarative-qmlplugins \
    qtmultimedia \
    qtconnectivity \
    qtlocation \
    qtlocation-qmlplugins \
    qtpositioning \
    qtpositioning-qmlplugins \
    qt5compat \
    bluez5 \
    pulseaudio \
    weston \
"

do_prepare_sources() {
    src="${HEADUNIT_SRC}"
    if [ ! -d "${src}" ]; then
        bberror "HeadUnit sources not found at ${src}"
        exit 1
    fi

    rm -rf ${S}
    mkdir -p ${S}
    cp -a "${src}"/. ${S}/

    # Drop developer-only build directories that should not be staged
    find ${S} -maxdepth 1 -type d -name "build*" -exec rm -rf {} +
    rm -rf ${S}/.qtc_clangd
}

addtask prepare_sources after do_unpack before do_patch
do_prepare_sources[dirs] = "${WORKDIR}"

do_install:append() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/headunit.service ${D}${systemd_system_unitdir}/headunit.service
    install -m 0644 ${WORKDIR}/rfkill-unblock.service ${D}${systemd_system_unitdir}/rfkill-unblock.service
    install -d ${D}${sysconfdir}/dbus-1/system.d/
    install -m 0644 ${WORKDIR}/headunit-bluetooth.conf ${D}${sysconfdir}/dbus-1/system.d/headunit-bluetooth.conf
}

FILES:${PN} += "\
    ${bindir}/HeadUnitApp \
    ${datadir}/headunit \
    ${systemd_system_unitdir}/headunit.service \
    ${systemd_system_unitdir}/rfkill-unblock.service \
    ${sysconfdir}/dbus-1/system.d/headunit-bluetooth.conf \
"

SYSTEMD_SERVICE:${PN} = "headunit.service rfkill-unblock.service"
SYSTEMD_AUTO_ENABLE = "enable"
