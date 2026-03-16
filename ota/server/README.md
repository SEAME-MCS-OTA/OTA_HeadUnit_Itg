# OTA_GH (ota/server)

`ota/server`는 OTA_GH 서버(Flask), Dashboard(React), PostgreSQL, MQTT 설정을 담고 있는 디렉토리입니다.
처음 보는 사람은 아래 순서대로 실행하면 됩니다.

## 1. 이 디렉토리에서 할 수 있는 것

- OTA 서버 실행 (`server/`)
- OTA 대시보드 확인 (`dashboard/`)
- 펌웨어 업로드/트리거 테스트 (`scripts/` + API)
- 단독 compose 실행 (`docker-compose.yml`)

## 2. 먼저 알아둘 현재 동작

1. 업로드 파일은 로컬 `firmware_files/`에 영구 저장되지 않습니다.
- 현재 서버는 업로드 스트림을 OCI Object Storage로 직접 전송합니다.
- OCI 업로드 실패 시 `/api/v1/admin/firmware`는 `502`를 반환합니다.

2. 트리거 전송 경로는 설정에 따라 달라집니다.
- `MQTT_COMMAND_ONLY=true`: MQTT로만 전송
- `MQTT_COMMAND_ONLY=false`: MQTT/HTTP fallback 혼합
- HTTP 경로는 `LOCAL_DEVICE_MAP` 설정을 사용합니다.

## 3. 빠른 시작 (처음 1회)

```bash
cd /home/jeongmin/OTA_HeadUnit_Itg/ota/server
chmod +x quickstart.sh
./quickstart.sh
```

기본 주소:
- API: `http://localhost:8080`
- Dashboard: `http://localhost:3001`
- PostgreSQL: `localhost:5432`
- MQTT: `localhost:1883`

## 4. 권장 실행 순서 (초심자용)

### 4-1. 서버 기동 확인

```bash
curl -sS http://localhost:8080/health
```

### 4-2. 펌웨어 준비

선택 A: 샘플 파일 생성 + 자동 업로드 (`scripts/create_firmware.sh`)

```bash
cd /home/jeongmin/OTA_HeadUnit_Itg/ota/server
chmod +x scripts/*.sh
./scripts/create_firmware.sh 1.0.1
```

선택 B: 직접 업로드 (`.raucb` 권장)

```bash
curl -sS -X POST http://localhost:8080/api/v1/admin/firmware \
  -F "file=@/home/jeongmin/OTA_HeadUnit_Itg/out/<bundle>.raucb" \
  -F "version=1.0.1" \
  -F "release_notes=Release 1.0.1" \
  -F "overwrite=true"
```

### 4-3. 차량 ID 확인

```bash
curl -sS http://localhost:8080/api/v1/vehicles
```

### 4-4. 업데이트 트리거

```bash
curl -sS -X POST http://localhost:8080/api/v1/admin/trigger-update \
  -H "Content-Type: application/json" \
  -d '{"vehicle_id":"vw-ivi-0026","version":"1.0.1","force":true}'
```

### 4-5. 상태 확인

```bash
./scripts/check_status.sh vw-ivi-0026
```

## 5. 주요 API

- `GET /health`: 서버 헬스체크
- `GET /api/v1/update-check?vehicle_id=<id>&current_version=<ver>`: 업데이트 확인
- `POST /api/v1/report`: 디바이스 상태 보고
- `GET /api/v1/vehicles`: 차량 목록
- `GET /api/v1/firmware`: 펌웨어 목록
- `POST /api/v1/admin/firmware`: 펌웨어 업로드 (OCI로 직접 전송)
- `POST /api/v1/admin/trigger-update`: 업데이트 트리거

## 6. 환경 변수

### 6-1. 단독 실행(`ota/server/docker-compose.yml`)에서 주로 보는 키

- DB: `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_PORT`
- 서버: `SERVER_PORT`, `SECRET_KEY`, `DEBUG`, `LOG_LEVEL`
- 다운로드 URL: `FIRMWARE_BASE_URL`
- 트리거: `LOCAL_DEVICE_MAP`, `MQTT_COMMAND_ONLY`
- MQTT: `MQTT_BROKER_HOST`, `MQTT_BROKER_PORT`
- OCI: `OCI_REGION`, `OCI_NAMESPACE`, `OCI_BUCKET`, `OCI_PAR_TOKEN`, `OCI_FIRMWARE_PREFIX`

### 6-2. 루트 통합 스택(`docker-compose.ota-stack.yml`)에서의 대응 키

루트 스택에서는 같은 의미의 키를 `OTA_GH_` 접두어로 사용합니다.

예:
- `FIRMWARE_BASE_URL` -> `OTA_GH_FIRMWARE_BASE_URL`
- `LOCAL_DEVICE_MAP` -> `OTA_GH_LOCAL_DEVICE_MAP`
- `OCI_PAR_TOKEN` -> `OTA_GH_OCI_PAR_TOKEN`

## 7. 디렉토리 요약

```text
ota/server/
├── server/              # Flask API
├── dashboard/           # React dashboard
├── scripts/             # create_firmware.sh, check_status.sh
├── firmware_files/      # 로컬 작업용 디렉토리(현재 업로드 영구 저장소로는 미사용)
├── docker-compose.yml   # ota/server 단독 실행용
└── quickstart.sh
```

## 8. 자주 발생하는 문제

1. `/api/v1/admin/firmware`가 `502` 반환
- 원인: OCI 설정(특히 `OCI_PAR_TOKEN`) 오류
- 조치: OCI 관련 env 확인 후 재기동

2. `Firmware URL resolves to localhost`
- 원인: `FIRMWARE_BASE_URL`(또는 `OTA_GH_FIRMWARE_BASE_URL`)이 localhost
- 조치: 디바이스가 접근 가능한 Host IP URL로 변경

3. `Failed to send update command`
- 원인: `LOCAL_DEVICE_MAP` 오설정, MQTT 미연결, 디바이스 서비스 비정상
- 조치: `vehicle_id`, 네트워크 도달성, `ota-backend` 상태 확인

## 9. 종료

단독 실행을 quickstart로 올렸다면:

```bash
cd /home/jeongmin/OTA_HeadUnit_Itg/ota/server
docker compose down
```

통합 스택으로 올렸다면 루트에서:

```bash
cd /home/jeongmin/OTA_HeadUnit_Itg
./ota/tools/ota-stack-down.sh
```
