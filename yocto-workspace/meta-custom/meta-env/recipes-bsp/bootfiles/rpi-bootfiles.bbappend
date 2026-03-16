# Deploy Seeed CAN-FD HAT v2 overlay to /boot/overlays/
#
# This bbappend ensures the seeed-can-fd-hat-v2.dtbo overlay file
# is copied from the kernel build to /boot/overlays/ in the final image.

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

do_deploy:append() {
    # Copy the seeed-can-fd-hat-v2 overlay from kernel deploy to boot/overlays
    if [ -f ${DEPLOY_DIR_IMAGE}/seeed-can-fd-hat-v2.dtbo ]; then
        install -d ${DEPLOYDIR}/overlays
        install -m 0644 ${DEPLOY_DIR_IMAGE}/seeed-can-fd-hat-v2.dtbo ${DEPLOYDIR}/overlays/
        bbwarn "Deployed seeed-can-fd-hat-v2.dtbo to ${DEPLOYDIR}/overlays/"
    else
        bbwarn "seeed-can-fd-hat-v2.dtbo not found in ${DEPLOY_DIR_IMAGE}"
    fi
}

# Ensure this runs after kernel devicetree deployment
do_deploy[depends] += "linux-raspberrypi:do_deploy"
