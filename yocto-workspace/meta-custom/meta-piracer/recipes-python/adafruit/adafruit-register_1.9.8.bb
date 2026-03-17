SUMMARY = "CircuitPython data descriptor classes to represent hardware registers."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=6ec69d6e9e6c85adfb7799d7f8cf044e"

SRC_URI = "git://github.com/adafruit/Adafruit_CircuitPython_Register.git;protocol=https;nobranch=1"
SRCREV = "f2fe0eee14428aaff4ce24545cc99f8bd28f9486"
S = "${WORKDIR}/git"

inherit python3-dir

do_install() {
    install -d ${D}${PYTHON_SITEPACKAGES_DIR}
    cp -R ${S}/adafruit_register ${D}${PYTHON_SITEPACKAGES_DIR}/
}

FILES:${PN} = "${PYTHON_SITEPACKAGES_DIR}/adafruit_register"
