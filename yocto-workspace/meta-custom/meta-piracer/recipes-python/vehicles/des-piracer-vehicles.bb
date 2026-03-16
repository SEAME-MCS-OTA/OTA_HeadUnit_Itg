SUMMARY = "PiRacer vehicles module (provides PiRacerStandard)"
LICENSE = "CLOSED"

SRC_URI = "file://vehicles.py"
S = "${WORKDIR}"

inherit allarch python3-dir

do_install() {
    install -d ${D}${PYTHON_SITEPACKAGES_DIR}
    install -m 0644 "${WORKDIR}/vehicles.py" "${D}${PYTHON_SITEPACKAGES_DIR}/vehicles.py"
}

FILES:${PN} = "${PYTHON_SITEPACKAGES_DIR}/vehicles.py"
RDEPENDS:${PN} = " \
    python3-core \
    adafruit-blinka \
    adafruit-pureio \
    adafruit-platformdetect \
    adafruit-bus-device \
    adafruit-register \
    adafruit-pca9685 \
    adafruit-ina219 \
    adafruit-ssd1306 \
    rpi-gpio \
    adafruit-framebuf \
"
