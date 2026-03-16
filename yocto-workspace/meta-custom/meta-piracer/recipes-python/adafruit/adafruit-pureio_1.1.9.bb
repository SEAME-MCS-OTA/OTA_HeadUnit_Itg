SUMMARY = "Pure python access to Linux IO (I2C/SPI)."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=2a21fcca821a506d4c36f7bbecc0d009"

SRC_URI = "git://github.com/adafruit/Adafruit_Python_PureIO.git;protocol=https;nobranch=1"
SRCREV = "383b615ce9ff5bbefdf77652799f380016fda353"
S = "${WORKDIR}/git"

inherit python3-dir

do_install() {
    install -d ${D}${PYTHON_SITEPACKAGES_DIR}
    cp -R ${S}/Adafruit_PureIO ${D}${PYTHON_SITEPACKAGES_DIR}/
}

FILES:${PN} = "${PYTHON_SITEPACKAGES_DIR}/Adafruit_PureIO"
