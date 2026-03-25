# OTA_HeadUnit_Itg

Raspberry Pi 4 기반 Head-Unit/Instrument-Cluster + RAUC OTA 디바이스 저장소입니다.

## 범위
- 디바이스 OTA 백엔드(`ota/client`)
- RAUC 번들/키 관리(`ota/keys`)
- Yocto 이미지/번들 빌드(`yocto-workspace`, `ota/tools`)

서버(API/MQTT/DB/대시보드)는 별도 저장소 `OTA_SERVER_Itg`에서 운영합니다.

## 빠른 시작
```bash
cd /home/jeongmin/OTA_HeadUnit_Itg
./ota/tools/yocto-init.sh
```

## 빌드
```bash
# 이미지
./ota/tools/build-image.sh

# 번들
./ota/tools/build-rauc-bundle.sh
```

캐시로 변경 반영이 안 되면:
```bash
FORCE_REBUILD=1 ./ota/tools/build-image.sh
FORCE_REBUILD=1 ./ota/tools/build-rauc-bundle.sh
```

## 산출물
- 이미지: `out/des-image-raspberrypi4-64.rootfs.*`
- OTA 번들: `out/des-hu-bundle-raspberrypi4-64.raucb` (최신 timestamp 파일 alias)

## OTA 알림 반영
- `ota-backend`가 release announce 수신 시 system D-Bus signal 발행
- Head-Unit OTA 버튼이 해당 signal로 즉시 상태 반영
