SUMMARY = "CircuitPython INA219 current sensor"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=b49eaaf85ddbd7a185408c1bea270264"

SRC_URI = "git://github.com/adafruit/Adafruit_CircuitPython_INA219.git;protocol=https;nobranch=1"
SRCREV = "53f239d9dea9a206e593170fe2a209170fe0670a"
S = "${WORKDIR}/git"

inherit python3-dir

do_install() {
    install -d ${D}${PYTHON_SITEPACKAGES_DIR}
    install -m 0644 ${S}/adafruit_ina219.py ${D}${PYTHON_SITEPACKAGES_DIR}/
}

FILES:${PN} = "${PYTHON_SITEPACKAGES_DIR}/adafruit_ina219.py"
