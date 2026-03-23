# OTA E2E Test Guide

이 문서는 `/home/jeongmin/OTA_HeadUnit_Itg` 기준으로,
디바이스(HeadUnit) 측 OTA E2E를 수행하는 절차를 설명합니다.

중요:
- OTA 서버(API, MQTT, DB, Dashboard)는 별도 리포지토리 `OTA_SERVER_Itg`에서 운영합니다.

## 0. 용어

- Host: 이 저장소가 있는 개발 머신
- Device: OTA를 적용받는 대상 장치(예: Raspberry Pi)
- Server: `OTA_SERVER_Itg`에서 실행 중인 OTA 서버
- Bundle: OTA 대상 파일(`.raucb`)

## 1. 전체 실행 순서

1. 키/Yocto 환경 준비 (최초 1회)
2. 번들 빌드 (`./ota/tools/build-rauc-bundle.sh`)
3. 외부 서버(`OTA_SERVER_Itg`) 기동 및 상태 확인
4. 번들 업로드 (`POST /api/v1/admin/firmware`)
5. 차량 조회 (`GET /api/v1/vehicles`)
6. 업데이트 트리거 (`POST /api/v1/admin/trigger-update`)
7. 디바이스 로그/RAUC 상태 확인

## 2. 최초 1회 준비

### 2-1. 저장소 위치

```bash
cd /home/jeongmin/OTA_HeadUnit_Itg
```

### 2-2. 키 준비

```bash
./ota/tools/ota-generate-keys.sh
```

생성되는 키:
- `ota/keys/rauc/rauc.key.pem`
- `ota/keys/rauc/rauc.cert.pem`
- `ota/keys/ed25519/ota-signing.key`
- `ota/keys/ed25519/ota-signing.pub`

주의:
- 서버가 별도 리포지토리에서 명령 서명을 수행하므로, 서버 개인키와 디바이스 공개키(`ota-signing.pub`)는 반드시 동기화되어야 합니다.
- 디바이스에 배포된 공개키와 서버 서명키가 다르면 `SIGNATURE_VERIFY_FAILED`가 발생합니다.

### 2-3. Yocto 환경 초기화

```bash
./ota/tools/yocto-init.sh
```

## 3. 빌드 단계

### 3-1. (선택) 디바이스 이미지 빌드

```bash
./ota/tools/build-image.sh
```

### 3-2. (필수) RAUC 번들 빌드

```bash
./ota/tools/build-rauc-bundle.sh
```

산출물:
- `out/*.raucb`

## 4. 외부 서버 준비 (`OTA_SERVER_Itg`)

`OTA_SERVER_Itg`에서 서버/브로커/API를 실행한 뒤,
아래 기준으로 접근 가능한 상태인지 확인합니다.

- API base URL 예: `http://<SERVER_IP>:8080`
- Device가 접근 가능한 firmware URL이 서버 설정에 반영되어 있어야 함

## 5. E2E 실행

### 5-1. 번들 업로드

```bash
cd /home/jeongmin/OTA_HeadUnit_Itg
BUNDLE="$(ls -t out/*.raucb | head -n1)"
VERSION="1.0.1-e2e1"
SERVER_BASE_URL="http://<SERVER_IP>:8080"

curl -sS -X POST "${SERVER_BASE_URL}/api/v1/admin/firmware" \
  -F "file=@${BUNDLE}" \
  -F "version=${VERSION}" \
  -F "release_notes=E2E ${VERSION}" \
  -F "overwrite=true"
```

### 5-2. 차량 ID 확인

```bash
curl -sS "${SERVER_BASE_URL}/api/v1/vehicles"
```

### 5-3. 업데이트 트리거

```bash
VEHICLE_ID="vw-ivi-0026"

curl -sS -X POST "${SERVER_BASE_URL}/api/v1/admin/trigger-update" \
  -H "Content-Type: application/json" \
  -d "{\"vehicle_id\":\"${VEHICLE_ID}\",\"version\":\"${VERSION}\",\"force\":true}"
```

## 6. 성공 판정

### 6-1. Device 로그

```bash
journalctl -u ota-backend -f
```

정상 흐름:
1. `SIGNATURE OK`
2. `VERIFY OK`
3. RAUC install 성공
4. `POST_WRITE OK`
5. 재부팅 후 target slot 활성화

### 6-2. RAUC 상태

```bash
rauc status --output-format=json
```

## 7. 자주 발생하는 실패

1. `SIGNATURE_VERIFY_FAILED`
- 원인: 서버 개인키와 디바이스 공개키 불일치
- 조치: `OTA_SERVER_Itg`의 서명키와 디바이스 공개키 동기화

2. 번들 다운로드 실패
- 원인: 서버의 firmware URL 설정 불일치/접근 불가
- 조치: Device에서 접근 가능한 URL로 서버 설정 수정

3. `Failed to send update command`
- 원인: vehicle 매핑/네트워크/디바이스 서비스 문제
- 조치: Device IP:PORT, `ota-backend` 상태, MQTT 연결 확인

## 8. 반복 테스트 최소 순서

1. `./ota/tools/build-rauc-bundle.sh`
2. 외부 서버에서 번들 업로드
3. 외부 서버에서 트리거
4. Device 로그 확인
