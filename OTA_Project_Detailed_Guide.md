# OTA Project Detailed Guide

이 문서는 `/home/jeongmin/OTA_HeadUnit_Itg` 통합 리포지토리에서
DES Head-Unit 시스템에 RAUC 기반 OTA를 적용/운영하는 전체 절차를 설명합니다.

## 1. 목표

1. DES 앱 스택 유지
- `Head-Unit`, `DES_Instrument-Cluster`, Weston/Qt6 유지

2. OTA 체계 통합
- `RAUC + ota-backend + OTA_GH + OTA_VLM` 기반으로 표준화

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
├── docker-compose.ota-stack.yml
├── ota/
│   ├── client/
│   ├── server/
│   ├── OTA_VLM/
│   ├── keys/
│   │   ├── rauc/
│   │   └── ed25519/
│   └── tools/
│       ├── yocto-init.sh
│       ├── build-image.sh
│       ├── build-rauc-bundle.sh
│       ├── ota-generate-keys.sh
│       ├── ota-stack-up.sh
│       └── ota-stack-down.sh
├── yocto-workspace/
└── out/
```

## 4. 최초 1회 준비

### 4-1. 필수 도구

- Docker / Docker Compose
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
- 키를 다시 생성하면 기존 디바이스 공개키와 불일치할 수 있습니다.
- 키를 재생성했다면 이미지/디바이스 키 배포도 같이 동기화해야 합니다.

### 4-3. Yocto 초기화

```bash
./ota/tools/yocto-init.sh
```

## 5. 빌드 절차

### 5-1. 디바이스 이미지 빌드 (필요한 경우)

```bash
./ota/tools/build-image.sh
```

산출물(예):
- `out/des-image-raspberrypi4-64.rootfs.wic.bz2`
- `out/des-image-raspberrypi4-64.rootfs.wic.bmap`
- `out/des-image-raspberrypi4-64.rootfs.ext4.bz2`

### 5-2. OTA 번들 빌드 (E2E 필수)

```bash
./ota/tools/build-rauc-bundle.sh
```

산출물:
- `out/*.raucb`

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

## 7. OTA 스택 실행

```bash
cd /home/jeongmin/OTA_HeadUnit_Itg
./ota/tools/ota-stack-up.sh
```

중지:

```bash
./ota/tools/ota-stack-down.sh
```

기본 포트:
- OTA_GH API: `8080`
- OTA_GH Dashboard: `3001`
- OTA_VLM Backend: `4000`
- OTA_VLM DB(host): `3307`

## 8. 통합 스택에서 중요한 환경 변수 (`.env`)

- `OTA_GH_FIRMWARE_BASE_URL`: 디바이스가 접근 가능한 펌웨어 다운로드 URL
- `OTA_GH_LOCAL_DEVICE_MAP`: HTTP 트리거 대상 매핑 (`vehicle_id@ip:port`)
- `OTA_GH_MQTT_COMMAND_ONLY`: MQTT only 여부
- `OTA_GH_OCI_REGION`, `OTA_GH_OCI_NAMESPACE`, `OTA_GH_OCI_BUCKET`, `OTA_GH_OCI_PAR_TOKEN`
- `OTA_GH_COMMAND_SIGN_KEY_PATH`: OTA 명령 서명 개인키 경로

예시:

```dotenv
OTA_GH_FIRMWARE_BASE_URL=http://192.168.86.33:8080
OTA_GH_LOCAL_DEVICE_MAP=vw-ivi-0026@192.168.86.250:8080
OTA_GH_MQTT_COMMAND_ONLY=false
```

## 9. E2E 실행 순서 (실무 기준)

1. `./ota/tools/build-rauc-bundle.sh`
2. `./ota/tools/ota-stack-up.sh`
3. 디바이스 상태 확인 (`ota-backend`, `rauc`)
4. 번들 업로드 (`POST /api/v1/admin/firmware`)
5. 차량 확인 (`GET /api/v1/vehicles`)
6. 트리거 (`POST /api/v1/admin/trigger-update`)
7. 디바이스/서버 로그로 성공 판정

업로드 예시:

```bash
curl -sS -X POST http://localhost:8080/api/v1/admin/firmware \
  -F "file=@/home/jeongmin/OTA_HeadUnit_Itg/out/<bundle>.raucb" \
  -F "version=1.0.0-test" \
  -F "release_notes=E2E test" \
  -F "overwrite=true"
```

트리거 예시:

```bash
curl -sS -X POST http://localhost:8080/api/v1/admin/trigger-update \
  -H "Content-Type: application/json" \
  -d '{"vehicle_id":"vw-ivi-0026","version":"1.0.0-test","force":true}'
```

## 10. 반드시 알아둘 현재 동작

1. OTA_GH 업로드는 OCI Object Storage 전제입니다.
- 현재 구현은 업로드 스트림을 OCI로 직접 PUT 합니다.
- OCI 업로드 실패 시 업로드 API는 성공 처리하지 않고 `502`를 반환합니다.

2. `ota/server/firmware_files`는 현재 영구 업로드 저장소가 아닙니다.
- compose 볼륨/작업 디렉토리 용도로 남아있지만, 업로드 기본 경로는 OCI입니다.

## 11. 자주 발생하는 이슈

1. `Failed to upload firmware to OCI` (HTTP 502)
- 원인: `OTA_GH_OCI_*` 설정 오류(특히 PAR 토큰)
- 조치: `.env` 수정 후 스택 재기동

2. `Firmware URL resolves to localhost`
- 원인: `OTA_GH_FIRMWARE_BASE_URL` 오설정
- 조치: 디바이스가 접근 가능한 Host IP URL 사용

3. `SIGNATURE_VERIFY_FAILED`
- 원인: 서버 개인키와 디바이스 공개키 불일치
- 조치: 키 재생성/배포 절차 동기화

4. `Failed to send update command`
- 원인: `OTA_GH_LOCAL_DEVICE_MAP` 오설정, MQTT 미연결, 디바이스 서비스 비정상
- 조치: `vehicle_id`, 네트워크, `ota-backend` 상태 확인

5. 포트 충돌 (`8080`, `3001`, `4000`, `3307`)
- 원인: 기존 컨테이너 점유
- 조치: 기존 스택 종료 후 재기동

## 12. 운영 권장사항

1. 키 재생성은 변경 계획과 함께 수행
2. 초기 이미지(`wic`)와 OTA 번들(`raucb`) 역할 분리
3. E2E 성공 로그 패턴을 팀 체크리스트로 고정
4. OTA 실패/복구(롤백) 시나리오를 별도 런북으로 유지

## 13. 관련 문서

- `OTA_E2E_TEST_GUIDE.md`
- `ARCHITECTURE.md`
- `ota/server/README.md`
