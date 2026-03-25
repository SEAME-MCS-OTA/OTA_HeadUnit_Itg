# Head-Unit

Qt/QML 기반 차량 Head-Unit 앱입니다.

## 주요 기능
- 홈/음악/환경/공조/블루투스/내비 화면
- 기어 D-Bus 연동
- OTA 상태 표시 및 업데이트 요청

## 요구 사항
- Qt 6.5+
- CMake

## 로컬 빌드
```bash
cd Head-Unit
cmake -S . -B build -DCMAKE_PREFIX_PATH=/home/jeongmin/Qt/6.9.3/gcc_64
cmake --build build
```

실행(개발 환경):
```bash
DES_GEAR_USE_SESSION_BUS=1 build/HeadUnitApp
```

## D-Bus
- Gear: `com.des.vehicle` / `/com/des/vehicle/Gear` / `com.des.vehicle.Gear`
- OTA 알림: `/com/des/ota/Status` / `com.des.ota.Status1` / `UpdateAvailabilityChanged`
