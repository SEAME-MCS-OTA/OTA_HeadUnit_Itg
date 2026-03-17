# OTA_HeadUnit_Itg

라즈베리파이에서 OTA 서버를 운영하기 위한 서버 전용 최소 구성 저장소입니다.

## 포함 서비스

- `ota_gh_postgres`: OTA 메타데이터 저장 DB
- `ota_gh_mosquitto`: MQTT 브로커
- `ota_gh_server`: OTA API 서버(Flask, 다운로드 엔드포인트 포함)
- `ota_gh_dashboard`: OTA 대시보드

## 요구사항

- Docker
- Docker Compose v2 (`docker compose`)
- 포트 사용 가능: `8080`, `3001`, `1883`, `9001`

## 실행

```bash
cd /home/yg/OTA_HeadUnit_Itg
./ota/tools/ota-stack-up.sh
```

## 중지

```bash
cd /home/yg/OTA_HeadUnit_Itg
./ota/tools/ota-stack-down.sh
```

## 기본 주소

- API: `http://localhost:8080`
- Dashboard: `http://localhost:3001`
- MQTT TCP: `localhost:1883`
- MQTT WS: `localhost:9001`

## 기본 점검

```bash
curl -sS http://localhost:8080/health
docker compose -f docker-compose.ota-stack.yml ps
```

## 주요 API

- `GET /health`
- `GET /api/v1/vehicles`
- `GET /api/v1/firmware`
- `POST /api/v1/admin/firmware`
- `POST /api/v1/admin/trigger-update`
- `GET /firmware/<filename>`

## 환경 변수

- `OTA_GH_OCI_PAR_TOKEN`: OCI 업로드/다운로드에 필수
- `OTA_GH_OCI_REGION`, `OTA_GH_OCI_NAMESPACE`, `OTA_GH_OCI_BUCKET`, `OTA_GH_OCI_FIRMWARE_PREFIX`: OCI 경로 설정
- `OTA_GH_FIRMWARE_BASE_URL`: 디바이스가 접근 가능한 서버 URL
- `OTA_GH_MQTT_PORT`, `OTA_GH_MQTT_WS_PORT`, `OTA_GH_SERVER_PORT`, `OTA_GH_DASHBOARD_PORT`: 포트 변경 시 사용

`ota-stack-up.sh`는 `OTA_GH_FIRMWARE_BASE_URL`이 비어 있으면 호스트 IP를 자동으로 계산해 `.env`에 기록합니다.

## 펌웨어 업로드 예시

```bash
curl -sS -X POST http://localhost:8080/api/v1/admin/firmware \
  -F "file=@/path/to/update.raucb" \
  -F "version=1.0.0" \
  -F "release_notes=Initial release" \
  -F "overwrite=true"
```

## 중요 동작

- 업로드 API는 파일을 로컬 영구 저장하지 않고 OCI Object Storage로 직접 전송합니다.
- 다운로드 API(`GET /firmware/<filename>`)는 OCI URL로 리다이렉트합니다.
- `OTA_GH_OCI_PAR_TOKEN`이 없거나 OCI 설정이 틀리면 업로드/다운로드가 실패합니다.

## 디렉토리 구조

```text
OTA_HeadUnit_Itg/
├── docker-compose.ota-stack.yml
├── ota/
│   ├── keys/ed25519/
│   ├── server/
│   │   ├── server/
│   │   ├── dashboard/
│   │   ├── mosquitto/
│   │   ├── schema.sql
│   │   └── firmware_files/
│   └── tools/
└── README.md
```
