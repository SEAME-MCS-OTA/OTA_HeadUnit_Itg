SUMMARY = "DES Head-Unit base image"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"
inherit core-image
inherit sdcard_image-rpi

BOOT_SPACE = "98304"

IMAGE_FEATURES += "ssh-server-openssh package-management"

IMAGE_INSTALL:append = " \
    packagegroup-core-buildessential \
    iproute2 can-utils \
    wpa-supplicant \
    connman connman-client \
    qtbase qtbase-plugins qtdeclarative qtmultimedia qtwayland \
    qtdeclarative-plugins qtdeclarative-qmlplugins qtshadertools \
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good alsa-utils ca-certificates \
    pulseaudio \
    pulseaudio-server \
    pulseaudio-module-loopback \
    bluez-alsa \
    fontconfig fontconfig-utils \
    ttf-dejavu-sans ttf-dejavu-sans-mono \
    liberation-fonts \
    ttf-noto-emoji-color \
    wayland weston weston-init weston-examples \
    libinput \
    evtest \
    i2c-dev-autoload \
    headunit \
    instrument-cluster \
    des-gear-dbus-config \
    can1 \
    piracer-controller \
    des-piracer-vehicles \
    plymouth \
    plymouth-set-default-theme \
    rauc \
    ota-backend \
    python3-core \
    python3-requests \
    python3-flask \
    python3-paho-mqtt \
    openssl \
    e2fsprogs \
    wifi-auto-enable \
"

add_users_to_groups() {
    sed -i 's/root:x:0:0:root:\/root:\/bin\/sh/root:x:0:0:root:\/root:\/bin\/bash/' ${IMAGE_ROOTFS}/etc/passwd
    groupadd bluetooth -R ${IMAGE_ROOTFS}
    usermod -a -G audio root -R ${IMAGE_ROOTFS}
    # pulse user for PulseAudio, bluealsa for bluez-alsa
    usermod -a -G bluetooth pulse -R ${IMAGE_ROOTFS} || true
    usermod -a -G audio bluealsa -R ${IMAGE_ROOTFS} || true
    usermod -a -G bluetooth bluealsa -R ${IMAGE_ROOTFS} || true
}

enable_pulseaudio_service() {
    # Manually enable pulseaudio.service for automatic startup
    if [ -f ${IMAGE_ROOTFS}/usr/lib/systemd/system/pulseaudio.service ]; then
        mkdir -p ${IMAGE_ROOTFS}/etc/systemd/system/multi-user.target.wants
        ln -sf /usr/lib/systemd/system/pulseaudio.service \
               ${IMAGE_ROOTFS}/etc/systemd/system/multi-user.target.wants/pulseaudio.service
        bbnote "Enabled pulseaudio.service"
    else
        bbwarn "pulseaudio.service not found, skipping enablement"
    fi
}

add_ab_mount_fstab() {
    # Keep mount behavior identical between:
    # 1) rootfs.ext4 OTA artifacts (written to inactive slot), and
    # 2) rootfs-a inside initial .wic images.
    # This avoids slot-dependent differences (e.g., /boot mounted only on A).
    mkdir -p ${IMAGE_ROOTFS}/boot ${IMAGE_ROOTFS}/data

    # Remove existing entries first so this stays idempotent across rebuilds.
    sed -i -E '\|^[^#].*[[:space:]]/boot[[:space:]]|d' ${IMAGE_ROOTFS}/etc/fstab 2>/dev/null || true  #/boot 제거
    sed -i -E '\|^[^#].*[[:space:]]/data[[:space:]]|d' ${IMAGE_ROOTFS}/etc/fstab 2>/dev/null || true  #/data 제거

    # Pin to fixed SD partition nodes for this target layout:
    #   p1=/boot (vfat), p4=/data (ext4)
    # This avoids LABEL resolution issues seen on some boots.
    echo 'LABEL=boot  /boot  vfat  defaults,nofail,x-systemd.device-timeout=10  0  2' >> ${IMAGE_ROOTFS}/etc/fstab   #RPi 부트체인 특성상 FAT 사용
    echo 'LABEL=data  /data  ext4  defaults,noatime,nofail,x-systemd.device-timeout=10  0  2' >> ${IMAGE_ROOTFS}/etc/fstab
}

ROOTFS_POSTPROCESS_COMMAND += " add_users_to_groups; enable_pulseaudio_service; add_ab_mount_fstab; "

# A/B OTA partition layout
WKS_FILE = "des-ab-sdimage.wks"

# A/B OTA: use wic.bz2 (A/B partition layout) + ext4 (RAUC bundle input)
# and keep ext4.bz2 for archive/transport convenience.
# rpi-sdimg generates single-rootfs layout, incompatible with A/B
IMAGE_FSTYPES:remove = "rpi-sdimg"
IMAGE_FSTYPES:append = " wic.bz2 ext4 ext4.bz2"
