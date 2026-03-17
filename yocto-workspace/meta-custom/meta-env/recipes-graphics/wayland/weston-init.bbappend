FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Use custom weston.ini with dual HDMI configuration
SRC_URI += "file://weston.ini \
            file://systemd/weston.service \
            file://systemd/weston.socket \
            file://weston-default \
"

do_install:append() {
    # Install custom weston.ini for dual-display configuration
    install -D -m 0644 ${WORKDIR}/weston.ini ${D}${sysconfdir}/xdg/weston/weston.ini

    # Install custom weston.service with dual-display support
    install -D -m 0644 ${WORKDIR}/systemd/weston.service ${D}${systemd_system_unitdir}/weston.service

    # Install custom weston.socket
    install -D -m 0644 ${WORKDIR}/systemd/weston.socket ${D}${systemd_system_unitdir}/weston.socket

    # Install weston environment configuration
    install -D -m 0644 ${WORKDIR}/weston-default ${D}${sysconfdir}/default/weston
}
