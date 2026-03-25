# OTA Project Detailed Guide

이 문서는 `/home/jeongmin/OTA_HeadUnit_Itg`에서
디바이스 측 OTA 빌드/검증/운영 절차를 설명합니다.

중요:
- OTA 서버(API, MQTT, DB, Dashboard)는 별도 리포지토리 `OTA_SERVER_Itg`에서 운영합니다.
- 본 저장소는 클라이언트/Yocto/RAUC 중심입니다.

## 1. 목표

1. DES 앱 스택 유지
- `Head-Unit`, `DES_Instrument-Cluster`, Weston/Qt6 유지

2. 디바이스 OTA 체계 유지
- `RAUC + ota-backend` 기반 안정적 업데이트

3. 서버 리포지토리 분리
- 제어 plane은 `OTA_SERVER_Itg`에서 운영

## 2. 현재 OTA 구조 요약

- 플랫폼: Raspberry Pi 4 (`raspberrypi4-64`)
- 슬롯: A/B rootfs (`/dev/mmcblk0p2`, `/dev/mmcblk0p3`)
- 설치 명령: `rauc install <bundle.raucb>`
- 검증 체계:
  - OTA 명령 서명 검증(ed25519)
  - 번들 SHA256/size 검증
  - post-write 검증(`e2fsck`)

## 3. 저장소 핵심 경로

```text
OTA_HeadUnit_Itg/
├── OTA_Project_Detailed_Guide.md
├── OTA_E2E_TEST_GUIDE.md
├── ota/
│   ├── client/
│   ├── keys/
│   │   ├── rauc/
│   │   └── ed25519/
│   └── tools/
│       ├── yocto-init.sh
│       ├── build-image.sh
│       ├── build-rauc-bundle.sh
│       ├── ota-generate-keys.sh
├── yocto-workspace/
└── out/
```

## 4. 최초 1회 준비

### 4-1. 필수 도구

- Yocto 빌드 의존 패키지
- `bmaptool` (초기 플래싱 시)

### 4-2. 키 생성

```bash
cd /home/jeongmin/OTA_HeadUnit_Itg
./ota/tools/ota-generate-keys.sh
```

생성 경로:
- `ota/keys/rauc/rauc.key.pem`
- `ota/keys/rauc/rauc.cert.pem`
- `ota/keys/ed25519/ota-signing.key`
- `ota/keys/ed25519/ota-signing.pub`

주의:
- 서버 명령 서명키와 디바이스 공개키는 반드시 동기화되어야 합니다.
- 키 재생성 시 기존 디바이스와 불일치가 생길 수 있습니다.

### 4-3. Yocto 초기화

```bash
./ota/tools/yocto-init.sh
```

## 5. 빌드 절차

### 5-1. 디바이스 이미지 빌드 (필요 시)

```bash
./ota/tools/build-image.sh
```

코드 변경 반영이 누락되는 경우:

```bash
FORCE_REBUILD=1 ./ota/tools/build-image.sh
```

### 5-2. OTA 번들 빌드 (E2E 필수)

```bash
./ota/tools/build-rauc-bundle.sh
```

코드 변경 반영이 누락되는 경우:

```bash
FORCE_REBUILD=1 ./ota/tools/build-rauc-bundle.sh
```

산출물:
- `out/*.raucb`
- 권장 업로드 대상: `out/des-hu-bundle-raspberrypi4-64.raucb`

## 6. 초기 물리 플래싱 (첫 부팅용)

초기 플래싱은 `.raucb`가 아니라 `.wic.bz2 + .wic.bmap`을 사용합니다.

```bash
IMG_DIR=/home/jeongmin/OTA_HeadUnit_Itg/out
DEV=/dev/sdX

sudo umount ${DEV}?* 2>/dev/null || true
sudo umount ${DEV}p* 2>/dev/null || true

sudo bmaptool copy \
  --bmap "$IMG_DIR/des-image-raspberrypi4-64.rootfs.wic.bmap" \
  "$IMG_DIR/des-image-raspberrypi4-64.rootfs.wic.bz2" \
  "$DEV"

sync
```

## 7. 실제 OTA 제어 plane

실제 번들 업로드/트리거/API/MQTT 제어는 `OTA_SERVER_Itg`에서 수행합니다.

실행 순서(요약):
1. 이 리포에서 번들 빌드
2. `OTA_SERVER_Itg`에서 서버 기동
3. 서버 API로 업로드/트리거
4. 디바이스 로그/RAUC 상태로 판정

## 8. 자주 발생하는 이슈

1. `SIGNATURE_VERIFY_FAILED`
- 원인: 서버 개인키와 디바이스 공개키 불일치
- 조치: 키 동기화 후 재시도

2. 번들 다운로드 실패
- 원인: 서버 firmware URL 접근 불가
- 조치: 디바이스 기준 접근 가능한 URL 설정

3. 업데이트 트리거 실패
- 원인: vehicle 매핑/네트워크/MQTT/서비스 상태 이슈
- 조치: 서버 설정과 디바이스 상태를 함께 점검

## 9. 운영 권장사항

1. 서버 키 관리 책임은 `OTA_SERVER_Itg`로 일원화
2. 본 리포는 디바이스 빌드/번들/검증에 집중
3. 키 변경 시 서버-디바이스 동기화 절차를 변경관리로 운영

## 10. 관련 문서

- `OTA_E2E_TEST_GUIDE.md`
- `ARCHITECTURE.md`
- `README.md`
