# Debug Scripts

## collect-debug-logs.sh

Raspberry Pi에서 실행하여 디버그 정보를 수집하는 스크립트입니다.

### 사용 방법:

**1. Raspberry Pi로 스크립트 복사:**
```bash
scp /home/seame/DES_Head-Unit/scripts/collect-debug-logs.sh root@raspberrypi:/tmp/
```

**2. Raspberry Pi에서 실행:**
```bash
ssh root@raspberrypi
cd /tmp
chmod +x collect-debug-logs.sh
./collect-debug-logs.sh
```

**3. 생성된 로그를 개발 머신으로 복사:**
```bash
# Raspberry Pi에서 표시된 경로 사용
scp root@raspberrypi:/tmp/des-debug-logs-*.tar.gz /home/seame/DES_Head-Unit/logs/
```

**4. 로그 압축 해제 및 분석:**
```bash
cd /home/seame/DES_Head-Unit/logs/
tar -xzf des-debug-logs-*.tar.gz
cd des-debug-logs-*/
```

### 수집되는 정보:

- System information (kernel, hardware)
- Systemd service status (headunit, instrument-cluster)
- Journal logs (최근 200줄)
- Kernel boot messages (dmesg)
- KMS configuration files
- Qt plugins and eglfs status
- Font configuration
- DRM/KMS information
- Environment variables

### 출력 파일:

```
des-debug-logs-YYYYMMDD-HHMMSS/
├── system-info.log
├── services-status.log
├── headunit-journal.log
├── cluster-journal.log
├── dmesg.log
├── kms-config.log
├── qt-plugins.log
├── fonts.log
├── drm-info.log
└── environment.log
```
