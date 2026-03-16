SUMMARY = "CircuitPython APIs for CPython on Linux."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=fccd531dce4b989c05173925f0bbb76c"

SRC_URI = "git://github.com/adafruit/Adafruit_Blinka.git;protocol=https;nobranch=1"
SRCREV = "234688cf57e0cfd88b768a49b57ed630a4077551"
S = "${WORKDIR}/git"

RDEPENDS:${PN} = "libgpiod adafruit-pureio adafruit-platformdetect"

inherit python3-dir

do_install() {
    install -d ${D}${PYTHON_SITEPACKAGES_DIR}
    cp -R ${S}/src/* ${D}${PYTHON_SITEPACKAGES_DIR}/
}

# Drop the prebuilt libgpiod pulse helper binaries. They are provided as
# upstream convenience blobs but are built for ARM/GLIBC_2.4 and fail QA on
# our 64-bit Yocto target. Removing them disables PulseIn support but keeps
# the rest of Blinka functional.
do_install:append() {
    find ${D}${PYTHON_SITEPACKAGES_DIR}/adafruit_blinka -name "libgpiod_pulsein*" -delete
    find ${D}${PYTHON_SITEPACKAGES_DIR}/adafruit_blinka -path "*/pulseio/.debug" -type d -exec rm -rf {} +
}

FILES:${PN} = "${PYTHON_SITEPACKAGES_DIR}/*"
