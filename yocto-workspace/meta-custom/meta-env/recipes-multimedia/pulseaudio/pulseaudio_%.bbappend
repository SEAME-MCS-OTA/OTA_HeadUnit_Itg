FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://system.pa.append \
            file://pulseaudio.service \
            file://pulseaudio-tmpfiles.conf \
"

inherit systemd

# PulseAudio service configuration for systemd
SYSTEMD_SERVICE:pulseaudio-server = "pulseaudio.service"
SYSTEMD_AUTO_ENABLE:pulseaudio-server = "enable"

# Bluetooth handled by bluealsa instead of PulseAudio
# RDEPENDS:pulseaudio-server += "pulseaudio-module-bluetooth-discover pulseaudio-module-bluetooth-policy pulseaudio-module-bluez5-device pulseaudio-module-bluez5-discover"

do_install:append() {
    # Append Bluetooth modules to system.pa
    cat ${WORKDIR}/system.pa.append >> ${D}${sysconfdir}/pulse/system.pa

    # Install systemd service
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/pulseaudio.service ${D}${systemd_system_unitdir}/

    # Install tmpfiles.d configuration for runtime directories
    install -d ${D}${libdir}/tmpfiles.d
    install -m 0644 ${WORKDIR}/pulseaudio-tmpfiles.conf ${D}${libdir}/tmpfiles.d/pulseaudio.conf
}

FILES:${PN}-server += "${systemd_system_unitdir}/pulseaudio.service \
                       ${libdir}/tmpfiles.d/pulseaudio.conf \
"
