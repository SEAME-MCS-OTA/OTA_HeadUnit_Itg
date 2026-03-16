SUMMARY = "CircuitPython driver for PCA9685 (servo/ESC PWM)"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=e7eb6b599fb0cfb06485c64cd4242f62"

SRC_URI = "git://github.com/adafruit/Adafruit_CircuitPython_PCA9685.git;protocol=https;nobranch=1"
SRCREV = "1a11d746e4506ae7f2eff08f584a9d75257bbc8d"
S = "${WORKDIR}/git"

inherit python3-dir

do_install() {
    install -d ${D}${PYTHON_SITEPACKAGES_DIR}
    install -m 0644 ${S}/adafruit_pca9685.py ${D}${PYTHON_SITEPACKAGES_DIR}/
}

FILES:${PN} = "${PYTHON_SITEPACKAGES_DIR}/adafruit_pca9685.py"
