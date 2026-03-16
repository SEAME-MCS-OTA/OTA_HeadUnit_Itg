# OTA_HeadUnit_Itg

Raspberry Pi 4 기반 DES Head-Unit/Instrument-Cluster 환경에
RAUC 기반 OTA 체계를 통합한 프로젝트입니다.

## 프로젝트 개요

이 저장소는 차량 인포테인먼트(Head-Unit) 소프트웨어를
A/B 슬롯 기반으로 안전하게 업데이트하기 위한 OTA 전체 구성을 포함합니다.

핵심 목적:
- 디바이스 소프트웨어의 원격 업데이트 자동화
- 업데이트 무결성/서명 검증 기반의 안전한 배포
- 서버/대시보드 기반 운영 가시성 확보

## 주요 구성

### Device 영역
- `ota/client`: 디바이스 측 OTA 백엔드
- `rauc`: 번들 설치 및 슬롯 전환(A/B)
- Yocto 레시피(`yocto-workspace/meta-custom/meta-app/recipes-ota/*`):
  - `ota-backend`
  - `rauc`
  - `rauc-bundle`

### Server 영역
- `ota/server`: OTA_GH 서버(Flask API, DB, MQTT 연동, Dashboard)
- `docker-compose.ota-stack.yml`: OTA_GH + OTA_VLM 통합 스택 구성

### Monitoring 영역
- `ota/OTA_VLM`: OTA 결과 관제/분석 대시보드

## OTA 동작 모델

- OTA 번들(`.raucb`)을 서버에 등록
- 서버가 디바이스에 업데이트 명령 전달(MQTT/HTTP)
- 디바이스가 번들 다운로드 후 검증(서명, SHA256/size)
- RAUC가 비활성 슬롯에 설치 후 슬롯 전환
- 결과 상태를 서버/대시보드로 수집

## 저장소 핵심 경로

```text
OTA_HeadUnit_Itg/
├── ota/
│   ├── client/
│   ├── server/
│   ├── OTA_VLM/
│   ├── keys/
│   └── tools/
├── yocto-workspace/
├── out/
├── docker-compose.ota-stack.yml
├── OTA_E2E_TEST_GUIDE.md
├── OTA_Project_Detailed_Guide.md
└── ARCHITECTURE.md
```

## 문서 안내

- [OTA_E2E_TEST_GUIDE.md](./OTA_E2E_TEST_GUIDE.md)
: 실제 E2E 테스트 실행 절차 및 검증 포인트

- [OTA_Project_Detailed_Guide.md](./OTA_Project_Detailed_Guide.md)
: 빌드/배포/운영 관점의 상세 가이드

- [ARCHITECTURE.md](./ARCHITECTURE.md)
: 시스템 아키텍처 및 구성 관계
