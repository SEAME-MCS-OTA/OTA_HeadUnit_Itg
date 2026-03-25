# scripts

## collect-debug-logs.sh
Raspberry Pi에서 로그를 모아 tar.gz로 생성합니다.

### 사용
```bash
# 1) 스크립트 복사
scp /home/jeongmin/OTA_HeadUnit_Itg/scripts/collect-debug-logs.sh root@raspberrypi:/tmp/

# 2) Pi에서 실행
ssh root@raspberrypi
cd /tmp
chmod +x collect-debug-logs.sh
./collect-debug-logs.sh

# 3) 결과 가져오기
scp root@raspberrypi:/tmp/des-debug-logs-*.tar.gz /home/jeongmin/OTA_HeadUnit_Itg/logs/
```
