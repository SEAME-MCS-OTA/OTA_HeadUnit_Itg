# OTA E2E Test Guide

이 문서는 `/home/jeongmin/OTA_HeadUnit_Itg` 기준으로,
이 시스템을 처음 보는 사람도 RAUC OTA End-to-End 테스트를 따라할 수 있게 정리한 가이드입니다.

## 0. 이 문서에서 쓰는 용어

- Host: 이 저장소가 있는 개발 PC/서버
- Device: OTA를 실제로 적용받는 대상 장치(예: Raspberry Pi)
- OTA_GH: Flask 기반 OTA 서버(`docker-compose.ota-stack.yml`의 `ota_gh_server`)
- Bundle: OTA 대상 파일(`.raucb`)

## 1. 실행 흐름 한눈에 보기

순서는 아래대로 진행하면 됩니다.

1. 키 생성 (`./ota/tools/ota-generate-keys.sh`) - 최초 1회
2. Yocto 초기화 (`./ota/tools/yocto-init.sh`) - 최초 1회 또는 환경 변경 시
3. 이미지 빌드 (`./ota/tools/build-image.sh`) - 디바이스가 구버전일 때만
4. 번들 빌드 (`./ota/tools/build-rauc-bundle.sh`) - E2E마다 필요
5. OTA 스택 기동 (`./ota/tools/ota-stack-up.sh`)
6. 번들 업로드 (`POST /api/v1/admin/firmware`)
7. `vehicle_id` 확인 (`GET /api/v1/vehicles`)
8. 업데이트 트리거 (`POST /api/v1/admin/trigger-update`)
9. 로그/상태로 성공 판정
10. 스택 종료 (`./ota/tools/ota-stack-down.sh`)

## 2. 최초 1회 준비

### 2-1. 저장소 위치

```bash
cd /home/jeongmin/OTA_HeadUnit_Itg
```

### 2-2. 키 생성 (최초 1회)

```bash
./ota/tools/ota-generate-keys.sh
```

생성되는 키:
- `ota/keys/rauc/rauc.key.pem`
- `ota/keys/rauc/rauc.cert.pem`
- `ota/keys/ed25519/ota-signing.key`
- `ota/keys/ed25519/ota-signing.pub`

주의:
- 디바이스에 이미 공개키를 배포한 뒤 키를 다시 생성하면, 서버 키와 디바이스 키가 불일치해서 `SIGNATURE_VERIFY_FAILED`가 발생할 수 있습니다.

### 2-3. Yocto 환경 초기화 (최초 1회)

```bash
./ota/tools/yocto-init.sh
```

이 스크립트는 `meta-rauc` 레이어 준비와 build dir 초기 설정을 처리합니다.

## 3. 테스트 전 필수 환경값 확인

루트 `.env`에서 아래 항목은 실제 네트워크에 맞아야 합니다.

- `OTA_GH_FIRMWARE_BASE_URL`
- `OTA_GH_LOCAL_DEVICE_MAP`
- `OTA_GH_OCI_REGION`
- `OTA_GH_OCI_NAMESPACE`
- `OTA_GH_OCI_BUCKET`
- `OTA_GH_OCI_PAR_TOKEN`

예시:

```dotenv
OTA_GH_FIRMWARE_BASE_URL=http://192.168.86.33:8080
OTA_GH_LOCAL_DEVICE_MAP=vw-ivi-0026@192.168.86.250:8080
```

설명:
- `OTA_GH_FIRMWARE_BASE_URL`: Device가 `.raucb`를 실제로 다운로드할 URL
- `OTA_GH_LOCAL_DEVICE_MAP`: OTA_GH가 HTTP 트리거를 보낼 Device 주소

## 4. 빌드 단계

### 4-1. (선택) 디바이스 이미지 빌드

디바이스가 최신 통합 이미지가 아니라면 실행하세요.

```bash
./ota/tools/build-image.sh
```

산출물:
- `out/*.wic.bz2`
- `out/*.ext4.bz2`

### 4-2. (필수) RAUC 번들 빌드

```bash
./ota/tools/build-rauc-bundle.sh
```

산출물:
- `out/*.raucb`

## 5. OTA 스택 기동

```bash
./ota/tools/ota-stack-up.sh
```

상태 확인:

```bash
docker compose -f docker-compose.ota-stack.yml ps
```

기본 포트:
- OTA_GH API: `8080`
- OTA_GH Dashboard: `3001`
- OTA_VLM Backend: `4000`

## 6. 디바이스 준비 상태 확인

Device에서:

```bash
systemctl status ota-backend rauc
journalctl -u ota-backend -n 200 --no-pager
ls -l /etc/ota-backend/keys/ota-signing.pub
```

Host에서 Device health 확인:

```bash
curl -sS http://<DEVICE_IP>:8080/health
```

## 7. E2E 실행

### 7-1. 번들 업로드

```bash
cd /home/jeongmin/OTA_HeadUnit_Itg
BUNDLE="$(ls -t out/*.raucb | head -n1)"
VERSION="1.0.1-e2e1"

curl -sS -X POST http://localhost:8080/api/v1/admin/firmware \
  -F "file=@${BUNDLE}" \
  -F "version=${VERSION}" \
  -F "release_notes=E2E ${VERSION}" \
  -F "overwrite=true"
```

정상이라면 `success: true`와 업로드된 `firmware` 정보가 반환됩니다.

참고:
- 현재 OTA_GH 업로드는 로컬 `/firmware_files`에 영구 저장하지 않고 OCI로 직접 업로드합니다.

### 7-2. 차량 ID 확인

```bash
curl -sS http://localhost:8080/api/v1/vehicles
```

여기서 실제 `vehicle_id` 값을 확인하세요.

### 7-3. 업데이트 트리거

```bash
VEHICLE_ID="vw-ivi-0026"

curl -sS -X POST http://localhost:8080/api/v1/admin/trigger-update \
  -H "Content-Type: application/json" \
  -d "{\"vehicle_id\":\"${VEHICLE_ID}\",\"version\":\"${VERSION}\",\"force\":true}"
```

`force=true`는 차량 온라인 윈도우/상태 검사로 막히는 경우 우회할 때 사용합니다.

## 8. 성공 판정 기준

### 8-1. Device 로그

```bash
journalctl -u ota-backend -f
```

아래 흐름이 순서대로 보이면 정상입니다.

1. `SIGNATURE OK` (명령 서명 검증 성공)
2. `VERIFY OK` (SHA256/size 검증 성공)
3. RAUC install 성공
4. `POST_WRITE OK`
5. 재부팅 후 target slot 활성화

### 8-2. RAUC 상태

```bash
rauc status --output-format=json
```

### 8-3. 서버 로그

```bash
docker compose -f docker-compose.ota-stack.yml logs -f ota_gh_server
```

## 9. 자주 발생하는 실패와 원인

1. `Failed to upload firmware to OCI` (HTTP 502)
원인: OCI PAR 토큰/버킷/리전 설정 오류
해결: `.env`의 `OTA_GH_OCI_*` 값 재확인 후 스택 재기동

2. `Firmware URL resolves to localhost`
원인: `OTA_GH_FIRMWARE_BASE_URL`이 localhost로 설정됨
해결: Device가 접근 가능한 Host IP URL로 변경

3. `SIGNATURE_VERIFY_FAILED`
원인: 서버 개인키와 Device 공개키 불일치
해결: 키 생성/배포 절차를 맞추고 Device 이미지(또는 키 파일) 동기화

4. `Failed to send update command`
원인: `OTA_GH_LOCAL_DEVICE_MAP` 오설정 또는 Device `ota-backend` 비활성
해결: Device IP:PORT 및 서비스 상태 점검

5. 포트 충돌 (`8080`, `3001`, `4000` 등)
원인: 기존 컨테이너가 포트 점유
해결: 기존 스택 중지 후 재기동

## 10. 반복 테스트 시 최소 실행 순서

두 번째 테스트부터는 보통 아래만 수행하면 됩니다.

1. `./ota/tools/build-rauc-bundle.sh`
2. `./ota/tools/ota-stack-up.sh` (이미 올라와 있으면 생략 가능)
3. 번들 업로드 (`POST /api/v1/admin/firmware`)
4. 트리거 (`POST /api/v1/admin/trigger-update`)
5. 로그 확인

## 11. 종료

```bash
cd /home/jeongmin/OTA_HeadUnit_Itg
./ota/tools/ota-stack-down.sh
```
