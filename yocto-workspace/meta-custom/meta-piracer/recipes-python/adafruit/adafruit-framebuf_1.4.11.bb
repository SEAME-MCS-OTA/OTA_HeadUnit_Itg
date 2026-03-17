SUMMARY = "Frame buffer manipulation for CircuitPython"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=6ad4a8854b39ad474755ef1aea813bac"

SRC_URI = "git://github.com/adafruit/Adafruit_CircuitPython_framebuf.git;protocol=https;branch=main"
SRCREV = "5c203073c9f7a13c4fecc45142251811b680387c"
S = "${WORKDIR}/git"

inherit python3-dir

do_install() {
    install -d ${D}${PYTHON_SITEPACKAGES_DIR}
    install -m 0644 ${S}/adafruit_framebuf.py ${D}${PYTHON_SITEPACKAGES_DIR}/
}

FILES:${PN} = "${PYTHON_SITEPACKAGES_DIR}/adafruit_framebuf.py"
