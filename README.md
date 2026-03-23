# OTA_HeadUnit_Itg

Raspberry Pi 4 기반 DES Head-Unit/Instrument-Cluster 환경에
RAUC 기반 OTA 클라이언트/빌드 체계를 통합한 프로젝트입니다.

## 프로젝트 개요

이 저장소는 차량 인포테인먼트(Head-Unit) 소프트웨어를
A/B 슬롯 기반으로 안전하게 업데이트하기 위한 디바이스 측 구성을 포함합니다.

핵심 목적:
- 디바이스 OTA 수신/검증/설치 자동화
- 번들 서명/무결성 검증 경로 유지
- Yocto 기반 이미지/번들 빌드 일원화

## 리포지토리 분리 정책

- 서버 API/MQTT/DB/대시보드는 별도 리포지토리 `OTA_SERVER_Itg`에서 운영합니다.

## 주요 구성

### Device 영역
- `ota/client`: 디바이스 측 OTA 백엔드
- `rauc`: 번들 설치 및 슬롯 전환(A/B)
- Yocto 레시피(`yocto-workspace/meta-custom/meta-app/recipes-ota/*`):
  - `ota-backend`
  - `rauc`
  - `rauc-bundle`

### Key 영역
- `ota/keys/rauc`: RAUC 번들 서명 키/인증서
- `ota/keys/ed25519`: OTA 명령 검증용 ed25519 키(디바이스 공개키 배포용)

## OTA 동작 모델

- 외부 OTA 서버(`OTA_SERVER_Itg`)가 OTA 명령을 디바이스로 전달
- 디바이스(`ota/client`)가 번들 다운로드 후 검증(서명, SHA256/size)
- RAUC가 비활성 슬롯에 설치 후 슬롯 전환
- 결과 상태가 외부 서버/관제로 수집

## 저장소 핵심 경로

```text
OTA_HeadUnit_Itg/
├── ota/
│   ├── client/
│   ├── keys/
│   └── tools/
├── yocto-workspace/
├── out/
├── OTA_E2E_TEST_GUIDE.md
├── OTA_Project_Detailed_Guide.md
└── ARCHITECTURE.md
```

## 문서 안내

- [OTA_E2E_TEST_GUIDE.md](./OTA_E2E_TEST_GUIDE.md)
: 디바이스 측 E2E 절차 및 검증 포인트

- [OTA_Project_Detailed_Guide.md](./OTA_Project_Detailed_Guide.md)
: 빌드/배포/운영 관점의 상세 가이드

- [ARCHITECTURE.md](./ARCHITECTURE.md)
: 시스템 아키텍처 및 구성 관계
