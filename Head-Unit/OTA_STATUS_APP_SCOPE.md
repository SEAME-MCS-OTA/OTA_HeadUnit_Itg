# OTA Status App Migration Scope (Step 1)

## 1) Goal

`OTA_img_raspi`의 OTA 상태 확인 화면(`OtaPage.qml`)을 현재 HeadUnit 앱에 이식한다.
이 문서는 구현 전에 범위/비범위/API 계약을 고정하기 위한 1차 스코프 문서다.

## 2) Entry Point (UI)

- 위치: Home 화면 우상단 기어 표시(`GearSelector`) 왼쪽
- 형태: `OTA` 전용 진입 버튼 1개
- 동작: 버튼 클릭 시 OTA 상태 페이지로 이동

## 3) In-Scope (MVP)

### A. 조회 기능 (필수)

- 현재 슬롯 표시 (`A/B`)
- 버전 정보 (`current_version`, `target_version`)
- OTA 진행 상태 (`phase`, `event`)
- 최근 OTA 로그 (`ota_log[]`)
- 에러 표시 (`last_error`)
- 네트워크/시간/디바이스 최소 상태 표시 (`ip`, `ip_source`, `device_id`, `device_model`, `ts`)

### B. 관리자 기능 (포함)

- OTA 시작 트리거 (`/ota/start`)
- 업데이트 요청 신호 발행 (`/ota/request-update`)
- 업로드 기능(외부 OTA 서버 firmware upload)은 같은 화면의 "Admin Mode"로 포함
  - 단, 로컬 `ota-backend` API에는 업로드 엔드포인트가 없으므로 외부 OTA 서버 API를 별도 호출해야 함
  - 최소 요구 API: `/api/v1/admin/firmware`, `/api/v1/firmware`
  - 네트워크/서버 주소가 없으면 업로드 UI는 비활성 상태로 표시

## 4) Out-of-Scope (Step 1 기준)

- 외부 OTA 서버 대시보드 수준의 전체 운영 화면(차량 전체 목록, 지도/통계 모니터링)
- 사용자 인증/권한 시스템 신규 도입
- OTA 실패 자동복구 로직 변경 (RAUC/ota-backend 로직 수정은 제외)
- 디자인 시스템 전면 개편

## 5) API Contract

### 5.1 Local OTA Backend (device-local)

- Base URL: `http://127.0.0.1:8080`
- `GET /ota/status`
- `POST /ota/start`
  - request: `{"ota_id":"...", "url":"...", "target_version":"..."}`
- `POST /ota/request-update`
  - request: `{"release_id":"...", "version":"..."}`

`GET /ota/status` expected fields:

- `ts`
- `device_id`
- `device_model`
- `compatible`
- `current_slot`
- `slots[]` (`name`, `state`, `bootname`, `device`)
- `ota_id`
- `ota_log[]`
- `current_version`
- `target_version`
- `phase`
- `event`
- `last_error`
- `ip`, `ip_source`

### 5.2 External OTA Admin API (for upload/admin mode)

- Base URL: runtime config (예: `http://<server-ip>:8080`)
- `POST /api/v1/admin/firmware` (multipart upload)
- `GET /api/v1/firmware` (업로드 결과/버전 확인)

## 6) Runtime Modes

- `Viewer Mode`:
  - 로컬 상태 조회 전용 + 트리거/재부팅
  - 기본 모드
- `Admin Mode`:
  - Viewer Mode + 외부 OTA 서버 업로드 기능
  - 서버 주소가 설정된 경우에만 활성

## 7) Acceptance Criteria (Step 1)

- Home 우상단에 `OTA` 진입 버튼 위치/동작이 명확히 정의됨
- 상태조회 표시 필드와 소스 API가 문서화됨
- 관리자 기능 범위(트리거/재부팅/업로드)와 제약(업로드는 외부 OTA 서버 API 의존)이 확정됨
- 다음 단계 구현(파일 추가/연결)이 바로 가능한 수준으로 범위 고정됨
