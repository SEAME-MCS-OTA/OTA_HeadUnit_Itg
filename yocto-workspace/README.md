# Yocto Workspace (OTA_HeadUnit_Itg)

`yocto-workspace/`는 DES 기반 이미지 위에 RAUC OTA 경로를 통합한
빌드 워크스페이스입니다.

## 레이어 구성

- `poky/`
- `meta-openembedded/`
- `meta-qt6/`
- `meta-raspberrypi/`
- `meta-custom/`
  - `meta-env`: distro/image/BSP
  - `meta-app`: 앱 + OTA 레시피
  - `meta-piracer`: CAN/컨트롤러

> RAUC 번들 빌드(`inherit bundle`)를 위해 `meta-rauc`가 필요합니다.
> `ota/tools/yocto-init.sh`가 `meta-rauc`를 준비하도록 구성되어 있습니다.

## OTA 관련 핵심 레시피

```text
meta-custom/meta-app/recipes-ota/
├── ota-backend/         # Python device OTA backend
├── rauc/                # RAUC system.conf + boot backend + mark-good/check
└── rauc-bundle/         # des-hu-bundle (.raucb)
```

- 제거됨: `des-ota-clientd` (기존 커스텀 OTA 클라이언트)

## 이미지 레시피

- `meta-custom/meta-env/recipes-core/images/des-image.bb`
  - `rauc`, `ota-backend` 포함
  - A/B WIC(`des-ab-sdimage.wks`) + OTA rootfs 산출물 유지

## 빠른 빌드

```bash
cd yocto-workspace
source poky/oe-init-build-env build-des

# 이미지
bitbake des-image

# RAUC 번들
bitbake des-hu-bundle
```

## 산출물

```text
build-des/tmp-glibc/deploy/images/raspberrypi4-64/
├── des-image-*.wic.bz2
├── des-image-*.ext4.bz2
└── des-hu-bundle-*.raucb
```

## 빌드 초기화 도우미

레포 루트에서:

```bash
./ota/tools/yocto-init.sh
```

이 스크립트는 다음을 보조합니다.

1. `meta-rauc` 준비
2. `build-des/conf` 초기화
3. `bblayers.conf`에 필요한 레이어 누락 시 보강
