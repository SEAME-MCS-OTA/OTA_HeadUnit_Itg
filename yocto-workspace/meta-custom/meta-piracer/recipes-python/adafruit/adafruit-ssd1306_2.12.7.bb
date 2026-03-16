SUMMARY = "CircuitPython SSD1306 OLED display"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=df3400dd14c520e98b9192195e8b82bb"

SRC_URI = "git://github.com/adafruit/Adafruit_CircuitPython_SSD1306.git;protocol=https;nobranch=1"
SRCREV = "e17c9d5c5d732b66f0523677f041a8e0f1d4bad3"
S = "${WORKDIR}/git"

inherit python3-dir

do_install() {
    install -d ${D}${PYTHON_SITEPACKAGES_DIR}
    install -m 0644 ${S}/adafruit_ssd1306.py ${D}${PYTHON_SITEPACKAGES_DIR}/
}

FILES:${PN} = "${PYTHON_SITEPACKAGES_DIR}/adafruit_ssd1306.py"
