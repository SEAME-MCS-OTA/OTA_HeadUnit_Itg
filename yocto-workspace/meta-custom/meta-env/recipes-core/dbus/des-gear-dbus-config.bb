SUMMARY = "D-Bus policy for DES vehicle gear interface"
LICENSE = "CLOSED"

SRC_URI = "file://com.des.vehicle.Gear.conf"

S = "${WORKDIR}"

inherit allarch

do_install() {
    install -d ${D}${sysconfdir}/dbus-1/system.d
    install -m 0644 ${WORKDIR}/com.des.vehicle.Gear.conf ${D}${sysconfdir}/dbus-1/system.d/com.des.vehicle.Gear.conf
}

FILES:${PN} = "${sysconfdir}/dbus-1/system.d/com.des.vehicle.Gear.conf"
