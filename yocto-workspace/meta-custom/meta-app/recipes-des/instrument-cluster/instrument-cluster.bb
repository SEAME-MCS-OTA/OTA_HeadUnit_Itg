SUMMARY = "Qt 6 instrument cluster application"
LICENSE = "CLOSED"

SRC_URI = "file://instrument-cluster.service \
"

S = "${WORKDIR}/InstrumentCluster"

inherit qt6-cmake systemd

IC_SRC ?= "${TOPDIR}/../../DES_Instrument-Cluster/Cluster-app"

DEPENDS = "\
    qtbase \
    qtdeclarative \
    qtdeclarative-native \
    qtmultimedia \
    qtwayland \
    qtwayland-native \
    qtshadertools-native \
    wayland \
"

RDEPENDS:${PN} = "\
    qtbase \
    qtwayland \
    qtdeclarative-plugins \
    qtdeclarative-qmlplugins \
    qtmultimedia \
    weston \
"

do_prepare_sources() {
    src="${IC_SRC}"
    if [ ! -d "${src}" ]; then
        bberror "Instrument Cluster sources not found at ${src}"
        exit 1
    fi

    rm -rf ${S}
    mkdir -p ${S}
    cp -a "${src}"/. ${S}/

    find ${S} -maxdepth 1 -type d -name "build*" -exec rm -rf {} +
    rm -rf ${S}/.qtc_clangd
}

addtask prepare_sources after do_unpack before do_patch
do_prepare_sources[dirs] = "${WORKDIR}"

do_install:append() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/instrument-cluster.service ${D}${systemd_system_unitdir}/instrument-cluster.service
}

FILES:${PN} += "\
    ${bindir}/appIC \
    ${datadir}/appIC \
    ${systemd_system_unitdir}/instrument-cluster.service \
"

SYSTEMD_SERVICE:${PN} = "instrument-cluster.service"
SYSTEMD_AUTO_ENABLE = "enable"
