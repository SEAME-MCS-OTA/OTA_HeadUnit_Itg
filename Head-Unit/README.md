# Head-Unit – Qt 6 Infotainment App

Qt 6(QML + C++) 기반 헤드유닛 UI 모듈입니다. 음악·앰비언트·기후 위젯과 기어 상태를 하나의 앱으로 통합하고, C++ 백엔드가 재사용 가능한 서비스(QMediaPlayer, Open‑Meteo API 등)를 제공합니다.

## 폴더 구조

```
Head-Unit/
├── CMakeLists.txt
├── design/
│   └── assets/               # 샘플 오디오·이미지
├── src/
│   ├── main.cpp              # QApplication 부트스트랩
│   ├── HeadUnit.*            # QML 엔진 초기화 및 컨텍스트 등록
│   ├── ViewModel.*           # Q_PROPERTY로 UI에 상태 노출
│   └── backend/
│       ├── gear/gear_client.*        # Instrument Cluster와 D-Bus 연동
│       ├── music/music_player.*      # QMediaPlayer 래퍼
│       └── weather/weather_service.* # Open‑Meteo REST 클라이언트
├── ui/
│   ├── main.qml
│   ├── components/
│   └── pages/
└── build/                    # 로컬 빌드 산출물(ignored)
```

## 빌드 & 실행

### 공통 요구 사항
- Qt 6.9 이상 (Core, Gui, Quick, Quick Controls, Multimedia, Network)
- FFmpeg 기반 Qt Multimedia 런타임
- 네트워크 연결 (날씨 갱신용)

### CMake CLI
```bash
cd Head-Unit
cmake -S . -B build/Desktop_Qt_6_9_3-Debug \
  -DCMAKE_PREFIX_PATH=/home/seame/Qt/6.9.3/gcc_64
cmake --build build/Desktop_Qt_6_9_3-Debug
DES_GEAR_USE_SESSION_BUS=1 \
  build/Desktop_Qt_6_9_3-Debug/HeadUnitApp
```
`DES_GEAR_USE_SESSION_BUS=1`은 개발용 랩톱에서 Instrument Cluster 앱과 동일한 세션 버스로 연결하기 위한 플래그입니다. 시스템 버스를 사용할 배포 환경(예: 라즈베리 파이)에서는 이 변수를 지정하지 않습니다.

### Qt Creator
1. `File > Open File or Project…`로 `Head-Unit/CMakeLists.txt`를 불러옵니다.
2. Kit를 `Desktop Qt 6.9.x` 로 선택 후 Configure.
3. `Projects > Run` 탭의 *Environment*에 `DES_GEAR_USE_SESSION_BUS=1`을 추가합니다.
4. Instrument Cluster 앱(`DES_Instrument-Cluster/Cluster-app`)을 먼저 실행한 뒤 Head-Unit을 구동합니다.

### D-Bus 연동 흐름
- 서비스명: `com.des.vehicle`, 오브젝트: `/com/des/vehicle/Gear`, 인터페이스: `com.des.vehicle.Gear`
- Instrument Cluster의 `GearManager`가 서비스를 등록하고 기어 변경을 브로드캐스트합니다.
- Head-Unit `GearClient`는 동일 버스에 접속해 `GetGear`, `RequestGear`, `GearChanged` 시그널을 사용합니다.

## Yocto 통합
- `work/meta-custom/meta-app/recipes-des/headunit/headunit.bb`가 이 디렉터리를 그대로 패키징합니다.
- 레시피는 `${TOPDIR}/../../Head-Unit`을 기본 소스 경로로 사용하므로, Yocto 빌드 전에 이 경로를 최신 상태로 유지하세요.
- `bitbake des-image` 실행 전 Head-Unit을 재빌드할 필요는 없지만, 변경 사항은 git에 반영하거나 `do_prepare_sources` 단계에서 복사되도록 관리해야 합니다.

## 자주 묻는 질문

| 증상 | 조치 |
| --- | --- |
| `[GearClient] DBus interface invalid` | Instrument Cluster 앱이 먼저 실행 중인지, 동일한 버스(세션/시스템)를 바라보는지 확인합니다. |
| 음악이 재생되지 않음 | Qt Multimedia 플러그인 설치 상태와 `design/assets/` 내 MP3 존재 여부 확인. |
| 날씨가 갱신되지 않음 | 네트워크 연결 및 Open‑Meteo API 응답(`curl`) 점검. 실패 시 로그에 에러 메시지가 출력됩니다. |
| QML import 에러 | `build/` 디렉터리를 지우고 `cmake --build`로 재생성하면 캐시가 초기화됩니다. |

## 라이선스

MIT License (루트 `LICENSE` 참조).
