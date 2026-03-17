# DES Instrument Cluster

Qt 6/QML로 작성된 계기판 애플리케이션과 지원 스크립트를 모아 둔 워크스페이스입니다. Head-Unit 앱과 같은 버스에서 기어 상태를 주고받으며, Arduino 기반 속도 센서와 라즈베리 파이 제어 스크립트까지 포함하고 있습니다.

## 폴더 구조

```
DES_Instrument-Cluster/
├── Arduino/              # 센서·모터 제어용 스케치
├── Cluster-app/          # Qt 6 계기판 애플리케이션 (appIC)
├── Pi-controller/        # 라즈베리 파이에서 실행되는 보조 스크립트
├── systemd/              # 서비스/타이머/타겟 유닛 파일
├── build-tool/           # Docker·크로스 컴파일 보조 스크립트
└── Documentation/        # 요구사항, 설계 문서, 다이어그램
```

## Cluster-app (appIC) 빌드 & 실행

### 요구 사항
- Qt 6.9 이상 + Wayland/OpenGL 런타임
- Raspberry Pi 4B (배포 대상) 혹은 Linux Desktop (개발용)
- CAN 인터페이스(HAT 또는 USB) + 해당 커널 모듈

### Desktop에서 실행
```bash
cd DES_Instrument-Cluster/Cluster-app
cmake -S . -B build/Desktop_Qt_6_9_3-Debug \
  -DCMAKE_PREFIX_PATH=/home/jeongmin/Qt/6.9.3/gcc_64
cmake --build build/Desktop_Qt_6_9_3-Debug
DES_GEAR_USE_SESSION_BUS=1 \
  build/Desktop_Qt_6_9_3-Debug/appIC
```
`DES_GEAR_USE_SESSION_BUS=1` 플래그를 사용하면 Head-Unit과 동일한 *세션* 버스로 연결됩니다. 실제 라즈베리 파이에서는 시스템 버스를 사용하므로 해당 변수를 지정하지 않습니다.

Qt Creator를 사용할 경우 `Projects > Run > Environment`에 같은 변수를 추가하면 됩니다.

### 애플리케이션 역할
- `Cluster-app/src/module/GearManager.*`  
  `com.des.vehicle` 서비스를 등록하고, 기어 변경 요청/응답을 처리합니다.
- `module` 이하 클래스들은 SharedMemory + CAN 데이터를 읽어 UI(ViewModel)에 반영합니다.
- `design/asset/`에 UI에서 사용하는 그래픽 리소스가 있습니다.

## D-Bus 연동
- 서비스: `com.des.vehicle`
- 오브젝트: `/com/des/vehicle/Gear`
- 인터페이스: `com.des.vehicle.Gear`
- 메서드: `GetGear`, `RequestGear`
- 시그널: `GearChanged(quint8 gear, QString source, quint32 seq)`, `GearRequestRejected(...)`

Head-Unit의 `gear_client`는 동일한 버스에서 위 인터페이스를 호출합니다. 개발 PC에서 두 앱을 함께 띄울 때는 **appIC → HeadUnitApp** 순서로 실행해 서비스가 먼저 등록되도록 합니다.

## 라즈베리 파이 배포
1. Yocto 이미지: `/home/jeongmin/yocto/work` 워크스페이스에서  
   ```bash
   . poky/oe-init-build-env build-des
   bitbake des-image
   ```  
   빌드하면 Head-Unit과 Cluster-app이 함께 포함된 이미지를 생성합니다.
2. Systemd 서비스: `systemd/*.service` 파일을 `/etc/systemd/system/`에 배포 후  
   ```bash
   sudo systemctl enable instrument-cluster.service
   sudo systemctl enable headunit.service
   sudo systemctl start instrument-cluster.service
   sudo systemctl start headunit.service
   ```  
   순서로 활성화합니다.

## Arduino/CAN 구성
- `Arduino/LM363_BasicSketch` : 기본 센서 테스트용
- `Arduino/SpeedSensor_CAN` : 속도 센서 값을 CAN 프레임으로 송신
- 라즈베리 파이 측 `Pi-controller` 스크립트와 `systemd/can-interface.service`가 SocketCAN 인터페이스를 준비합니다.

## 라이선스

MIT License (`LICENSE` 참조).

## Yocto 패키징 참고
- `meta-custom/meta-app` 레이어의 `instrument-cluster.bb`가 `Cluster-app` 소스를 Yocto 빌드에 포함합니다. 경로가 다르면 `IC_SRC` 변수를 수정하세요.
- `meta-custom/meta-piracer` 레이어의 `piracer-controller.bb`가 `Pi-controller` 스크립트와 systemd 유닛을 설치합니다. 빌드 시 `IMAGE_INSTALL`에 `piracer-controller`와 `can1` 패키지를 추가해야 자동으로 활성화됩니다.
- 실제 차량 제어를 위해서는 벤더에서 제공하는 `vehicles` 모듈(예: `DES_PiRacer-Assembly/piracer/vehicles.py`)이 필요합니다. 패키지에 포함하지 않으면 서비스는 경고만 출력하고 슬립 상태로 동작합니다.
