# DRAKVUF 설치 및 웹 UI 사용 매뉴얼 - Ubuntu 24.04 최적화

이 매뉴얼은 Ubuntu 24.04 LTS에서 DRAKVUF를 설치하고 웹 UI를 사용하는 방법을 상세히 설명합니다.

## 📋 목차

1. [시스템 요구사항](#시스템-요구사항)
2. [자동 설치 방법](#자동-설치-방법)
3. [웹 UI 사용법](#웹-ui-사용법)
4. [문제 해결 가이드](#문제-해결-가이드)
5. [고급 설정](#고급-설정)
6. [FAQ](#faq)

## 🖥️ 시스템 요구사항

### 필수 요구사항
- **운영체제**: Ubuntu 24.04 LTS (Noble Numbat)
- **CPU**: Intel VT-x 및 EPT 지원 (AMD CPU는 지원하지 않음)
- **메모리**: 최소 4GB RAM (8GB 권장)
- **디스크**: 최소 10GB 여유 공간 (20GB 권장)
- **네트워크**: 인터넷 연결 필요

### CPU 호환성 확인
```bash
# VT-x 및 EPT 지원 확인
egrep -o '(vmx|svm)' /proc/cpuinfo
cat /proc/cpuinfo | grep -E "(vmx|svm)"

# 가상화 활성화 확인 (BIOS에서 활성화되어야 함)
lscpu | grep Virtualization
```

## 🚀 자동 설치 방법

### 1단계: 저장소 클론
```bash
git clone https://github.com/yji0728/drakvuf.git
cd drakvuf
```

### 2단계: 자동 설치 스크립트 실행
```bash
sudo ./scripts/install_ubuntu24_automated.sh
```

### 3단계: 설치 진행 상황 모니터링
스크립트는 다음과 같은 단계로 진행됩니다:

1. **시스템 요구사항 확인** - CPU, 메모리, 디스크 공간 검증
2. **패키지 시스템 업데이트** - APT 저장소 업데이트
3. **의존성 패키지 설치** - 필수 개발 도구 및 라이브러리
4. **Go 언어 설치** - DRAKVUF 빌드용 Go 1.21.6
5. **DRAKVUF 패키지 설치** - 사전 빌드된 패키지 다운로드 및 설치
6. **Volatility3 설치** - 메모리 분석 도구
7. **설치 완료 및 검증** - GRUB 업데이트 및 재부팅 준비

### 4단계: 시스템 재부팅
```bash
sudo reboot
```

재부팅 후 GRUB 메뉴에서 **Xen 하이퍼바이저**를 선택하세요.

## 🌐 웹 UI 사용법

### 웹 UI 시작
```bash
cd drakvuf
./start_webui.sh
```

브라우저에서 `http://localhost:5000`으로 접속합니다.

### 주요 기능

#### 1. 대시보드 (`/`)
- 시스템 리소스 모니터링 (CPU, 메모리, 디스크)
- DRAKVUF 설치 및 실행 상태 확인
- 빠른 작업 버튼

#### 2. 설치 페이지 (`/installation`)
- 자동 설치 진행
- 실시간 설치 로그 모니터링
- 오류 발생 시 대응 옵션 제공

#### 3. 실시간 모니터링 (`/monitoring`)
- DRAKVUF 분석 시작/중지
- 실시간 출력 스트림
- 이벤트 필터링 및 통계

#### 4. 설정 페이지 (`/configuration`)
- 분석 대상 VM 설정
- 플러그인 활성화/비활성화
- 출력 형식 및 타임아웃 설정

#### 5. 로그 페이지 (`/logs`)
- 시스템 로그 조회
- 설치 로그 및 오류 로그 확인

## 🔧 문제 해결 가이드

### 일반적인 문제들

#### 1. 설치 스크립트 권한 오류
**문제**: `Permission denied` 오류
**해결**: 
```bash
chmod +x scripts/install_ubuntu24_automated.sh
sudo ./scripts/install_ubuntu24_automated.sh
```

#### 2. 패키지 다운로드 실패
**문제**: 네트워크 오류로 인한 패키지 다운로드 실패
**해결**:
```bash
# 네트워크 연결 확인
ping -c 4 google.com

# DNS 설정 확인
cat /etc/resolv.conf

# 방화벽 확인
sudo ufw status
```

#### 3. 의존성 패키지 설치 실패
**문제**: 필수 패키지 설치 중 오류
**해결**:
```bash
# APT 캐시 정리
sudo apt-get clean
sudo apt-get update

# 깨진 패키지 수정
sudo apt-get -f install

# 수동으로 의존성 설치
sudo apt-get install build-essential git wget curl cmake
```

#### 4. Xen 하이퍼바이저 부팅 실패
**문제**: 재부팅 후 Xen으로 부팅되지 않음
**해결**:
```bash
# GRUB 설정 확인
sudo nano /etc/default/grub

# GRUB 업데이트
sudo update-grub

# Xen 패키지 재설치
sudo apt-get install --reinstall xen-hypervisor-*
```

#### 5. 웹 UI 시작 실패
**문제**: Flask 애플리케이션 시작 오류
**해결**:
```bash
# Python 의존성 확인
pip3 install -r web_ui/requirements.txt

# 포트 충돌 확인
sudo netstat -tlnp | grep :5000

# 로그 확인
tail -f /var/log/drakvuf_webui.log
```

### 고급 문제 해결

#### 메모리 부족 문제
```bash
# 스왑 파일 생성 (4GB)
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 영구 스왑 설정
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

#### CPU 가상화 미지원 문제
```bash
# BIOS/UEFI에서 다음 옵션 활성화:
# - Intel VT-x / AMD-V
# - Intel EPT / AMD RVI
# - IOMMU

# 가상화 상태 재확인
sudo apt-get install cpu-checker
kvm-ok
```

#### 디스크 공간 부족 문제
```bash
# 디스크 사용량 확인
df -h
du -sh /* | sort -hr

# 불필요한 패키지 정리
sudo apt-get autoremove
sudo apt-get autoclean

# 로그 파일 정리
sudo journalctl --vacuum-time=7d
```

## ⚙️ 고급 설정

### 수동 DRAKVUF 설치
자동 설치가 실패하는 경우 수동으로 설치할 수 있습니다:

```bash
# 1. 의존성 설치
sudo ./package/depends.sh

# 2. 소스 빌드 (시간이 많이 소요됨)
./autogen.sh
make

# 3. 설치
sudo make install
```

### 웹 UI 포트 변경
```python
# web_ui/app.py 파일에서 포트 변경
socketio.run(
    app,
    host='0.0.0.0',
    port=8080,  # 원하는 포트로 변경
    debug=debug_mode
)
```

### SSL/HTTPS 설정
```bash
# 자체 서명 인증서 생성
openssl req -x509 -newkey rsa:4096 -nodes -out cert.pem -keyout key.pem -days 365

# Flask 앱에서 SSL 활성화
# app.py에 ssl_context=('cert.pem', 'key.pem') 추가
```

## ❓ FAQ

### Q: AMD CPU에서 사용할 수 있나요?
A: 아니요. DRAKVUF는 Intel VT-x 및 EPT 기술을 필요로 하므로 Intel CPU에서만 작동합니다.

### Q: 가상머신에서 DRAKVUF를 실행할 수 있나요?
A: 중첩 가상화(Nested Virtualization)가 지원되는 하이퍼바이저에서는 가능하지만, 성능이 크게 저하될 수 있습니다.

### Q: 설치 후 기존 커널로 부팅하고 싶습니다.
A: GRUB 메뉴에서 "Ubuntu"를 선택하면 기존 커널로 부팅됩니다. Xen을 완전히 제거하려면:
```bash
sudo apt-get remove xen-*
sudo update-grub
```

### Q: 웹 UI에 원격으로 접속할 수 있나요?
A: 보안상 기본적으로 localhost만 허용됩니다. 원격 접속이 필요한 경우 방화벽 설정과 함께 신중히 고려하세요.

### Q: DRAKVUF 분석 결과는 어디에 저장되나요?
A: 기본적으로 콘솔 출력으로 표시되며, 웹 UI에서 실시간으로 확인할 수 있습니다. 파일로 저장하려면 출력 리다이렉션을 사용하세요.

## 📞 지원

문제가 지속되는 경우:

1. **로그 파일 확인**:
   - `/var/log/drakvuf_install.log` - 설치 로그
   - `/var/log/drakvuf_errors.log` - 오류 로그
   - `/var/log/drakvuf_webui.log` - 웹 UI 로그

2. **시스템 정보 수집**:
```bash
# 시스템 정보 수집 스크립트
./scripts/install_ubuntu24_automated.sh --check-only
```

3. **GitHub Issues**: https://github.com/yji0728/drakvuf/issues

---

**마지막 업데이트**: 2024년 9월
**버전**: Ubuntu 24.04 최적화 v1.0