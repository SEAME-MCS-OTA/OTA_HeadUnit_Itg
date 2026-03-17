# OTA Server (ota/server)

서버 운영에 필요한 OTA 컴포넌트만 남긴 디렉토리입니다.

## 구성

- `server/`: Flask 기반 OTA API 서버
- `dashboard/`: React 대시보드
- `mosquitto/`: MQTT 브로커 설정 파일
- `schema.sql`: PostgreSQL 초기 스키마
- `firmware_files/`: 컨테이너 마운트 작업 디렉토리

## 루트에서 실행

```bash
cd /home/yg/OTA_HeadUnit_Itg
./ota/tools/ota-stack-up.sh
```

중지:

```bash
cd /home/yg/OTA_HeadUnit_Itg
./ota/tools/ota-stack-down.sh
```

## 접속 주소

- API: `http://localhost:8080`
- Dashboard: `http://localhost:3001`
- MQTT TCP: `localhost:1883`
- MQTT WS: `localhost:9001`

## 기본 확인

```bash
curl -sS http://localhost:8080/health
curl -sS http://localhost:8080/api/v1/vehicles
curl -sS http://localhost:8080/api/v1/firmware
```

## 주요 API

- `GET /health`
- `GET /api/v1/update-check`
- `POST /api/v1/report`
- `GET /api/v1/vehicles`
- `GET /api/v1/firmware`
- `POST /api/v1/admin/firmware`
- `POST /api/v1/admin/trigger-update`
- `GET /firmware/<filename>`

## 펌웨어 업로드 예시

```bash
curl -sS -X POST http://localhost:8080/api/v1/admin/firmware \
  -F "file=@/path/to/update.raucb" \
  -F "version=1.0.0" \
  -F "release_notes=Initial release" \
  -F "overwrite=true"
```

## 운영 시 주의

- 업로드는 로컬 파일 영구 저장이 아니라 OCI Object Storage 직접 업로드입니다.
- 다운로드 엔드포인트(`GET /firmware/<filename>`)는 OCI URL로 리다이렉트합니다.
- OCI 관련 환경 변수(`OTA_GH_OCI_*`)가 올바르지 않으면 업로드/다운로드가 실패합니다.
