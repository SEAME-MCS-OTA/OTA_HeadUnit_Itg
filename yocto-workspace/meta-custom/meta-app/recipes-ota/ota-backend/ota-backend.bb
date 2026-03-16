DESCRIPTION = "OTA backend service (RAUC-based)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = "file://ota-backend"

# Source from the project tree
OTA_BACKEND_SRC ?= "${TOPDIR}/../../ota/client"
OTA_ED25519_PUB ?= "${TOPDIR}/../../ota/keys/ed25519/ota-signing.pub"

inherit systemd

SYSTEMD_SERVICE:${PN} = "ota-backend.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

RDEPENDS:${PN} += " \
    python3-core \
    python3-fcntl \
    python3-logging \
    python3-requests \
    python3-flask \
    python3-paho-mqtt \
    rauc \
    "

FILES:${PN} += " \
    /usr/bin/ota-backend \
    /usr/lib/ota-backend \
    /usr/sbin/ota-backend-prepare-config.sh \
    /usr/lib/systemd/system/ota-backend.service \
    /etc/ota-backend \
    /etc/ota-backend/keys \
    "

do_install() {
    # Python application
    install -d ${D}/usr/lib/ota-backend
    cp -r ${OTA_BACKEND_SRC}/app ${D}/usr/lib/ota-backend/

    # Entry script
    install -d ${D}/usr/bin
    install -m 0755 ${WORKDIR}/ota-backend ${D}/usr/bin/ota-backend

    # Default config
    install -d ${D}/etc/ota-backend
    if [ -f ${OTA_BACKEND_SRC}/config/default-config.json ]; then
        install -m 0644 ${OTA_BACKEND_SRC}/config/default-config.json ${D}/etc/ota-backend/config.json
    fi

    # Command-signature public key (ed25519)
    install -d ${D}/etc/ota-backend/keys
    if [ -f ${OTA_ED25519_PUB} ]; then
        install -m 0644 ${OTA_ED25519_PUB} ${D}/etc/ota-backend/keys/ota-signing.pub
    else
        echo "ERROR: missing ed25519 public key: ${OTA_ED25519_PUB}" >&2
        echo "Run: ./ota/tools/ota-generate-keys.sh" >&2
        exit 1
    fi

    # Prepare-config helper
    install -d ${D}/usr/sbin
    if [ -f ${OTA_BACKEND_SRC}/systemd/ota-backend-prepare-config.sh ]; then
        install -m 0755 ${OTA_BACKEND_SRC}/systemd/ota-backend-prepare-config.sh ${D}/usr/sbin/ota-backend-prepare-config.sh
    fi

    # Systemd service
    install -d ${D}/usr/lib/systemd/system
    if [ -f ${OTA_BACKEND_SRC}/systemd/ota-backend.service ]; then
        install -m 0644 ${OTA_BACKEND_SRC}/systemd/ota-backend.service ${D}/usr/lib/systemd/system/ota-backend.service
    fi
}
