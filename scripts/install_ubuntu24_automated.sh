#!/bin/bash

#****************************************************************************#
# DRAKVUF 자동 설치 스크립트 - Ubuntu 24.04 최적화                               #
# 모든 로깅 활성화, 에러 대응 자동화, 단계별 모니터링                              #
#****************************************************************************#

set -e
set -o pipefail

# 로깅 설정
INSTALL_LOG="/var/log/drakvuf_install.log"
ERROR_LOG="/var/log/drakvuf_errors.log"
PROGRESS_FILE="/tmp/drakvuf_progress.txt"

# 색상 출력을 위한 설정
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로깅 함수들
log_info() {
    local message="$1"
    echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$INSTALL_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $message" >> "$INSTALL_LOG"
}

log_warn() {
    local message="$1"
    echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$INSTALL_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $message" >> "$INSTALL_LOG"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message" | tee -a "$ERROR_LOG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $message" >> "$ERROR_LOG"
}

log_step() {
    local step="$1"
    local message="$2"
    echo -e "${BLUE}[STEP $step]${NC} $message" | tee -a "$INSTALL_LOG"
    echo "$step: $message" > "$PROGRESS_FILE"
}

# 오류 처리 함수
error_handler() {
    local line_no=$1
    local error_code=$2
    local bash_lineno=$3
    local last_command="${BASH_COMMAND}"
    
    log_error "설치 중 오류 발생!"
    log_error "라인: $line_no, 오류 코드: $error_code"
    log_error "마지막 명령어: $last_command"
    
    echo "설치 실패: 오류 대응 옵션을 제공합니다."
    echo "1) 자동 정리 후 재시도"
    echo "2) 수동 정리 가이드 출력"
    echo "3) 로그 분석 도구 실행"
    echo "4) 종료"
    
    read -p "선택하세요 (1-4): " choice
    
    case $choice in
        1) cleanup_and_retry ;;
        2) show_manual_cleanup ;;
        3) analyze_logs ;;
        4) exit 1 ;;
        *) log_error "잘못된 선택"; exit 1 ;;
    esac
}

trap 'error_handler ${LINENO} $? ${BASH_LINENO}' ERR

# 시스템 정리 및 재시도
cleanup_and_retry() {
    log_info "시스템 정리 중..."
    apt-get --yes remove xen* libxen* drakvuf* || true
    apt-get autoremove -y || true
    apt-get autoclean || true
    log_info "정리 완료. 5초 후 재시도합니다..."
    sleep 5
    exec "$0" "$@"  # 스크립트 재실행
}

# 수동 정리 가이드
show_manual_cleanup() {
    cat << 'EOF'
=== 수동 정리 가이드 ===

1. 기존 패키지 제거:
   sudo apt-get --yes remove xen* libxen* drakvuf*
   sudo apt-get autoremove -y
   sudo apt-get autoclean

2. 설정 파일 정리:
   sudo rm -rf /etc/xen/
   sudo rm -rf /opt/volatility3/

3. 시스템 재부팅:
   sudo reboot

4. 재부팅 후 스크립트 다시 실행:
   sudo ./install_ubuntu24_automated.sh

=== 일반적인 문제 해결 ===

문제: "패키지를 찾을 수 없음"
해결: sudo apt-get update를 먼저 실행

문제: "의존성 문제"
해결: sudo apt-get -f install을 실행

문제: "권한 부족"
해결: sudo로 스크립트 실행

EOF
}

# 로그 분석 도구
analyze_logs() {
    log_info "로그 분석 중..."
    
    echo "=== 최근 오류 로그 ==="
    if [[ -f "$ERROR_LOG" ]]; then
        tail -20 "$ERROR_LOG"
    else
        echo "오류 로그가 없습니다."
    fi
    
    echo -e "\n=== 시스템 정보 ==="
    echo "Ubuntu 버전: $(lsb_release -d | cut -f2)"
    echo "커널 버전: $(uname -r)"
    echo "아키텍처: $(uname -m)"
    echo "메모리: $(free -h | grep Mem: | awk '{print $2}')"
    echo "디스크 공간: $(df -h / | awk 'NR==2{print $4}')"
    
    echo -e "\n=== 필수 패키지 확인 ==="
    for pkg in git wget curl cmake python3; do
        if dpkg -l | grep -q "^ii  $pkg "; then
            echo "✓ $pkg 설치됨"
        else
            echo "✗ $pkg 누락"
        fi
    done
}

# 시스템 요구사항 확인
check_system_requirements() {
    log_step "1" "시스템 요구사항 확인 중..."
    
    # Ubuntu 24.04 확인
    if ! grep -q "24.04" /etc/os-release; then
        log_warn "Ubuntu 24.04가 아닙니다. 호환성 문제가 발생할 수 있습니다."
        read -p "계속하시겠습니까? (y/n): " continue_install
        [[ "$continue_install" != "y" ]] && exit 1
    fi
    
    # 루트 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "이 스크립트는 root 권한으로 실행해야 합니다."
        echo "사용법: sudo $0"
        exit 1
    fi
    
    # 디스크 공간 확인 (최소 10GB)
    available_space=$(df / | awk 'NR==2{print $4}')
    if [[ $available_space -lt 10485760 ]]; then  # 10GB in KB
        log_error "디스크 공간이 부족합니다. 최소 10GB가 필요합니다."
        exit 1
    fi
    
    # 메모리 확인 (최소 4GB)
    total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    if [[ $total_mem -lt 4194304 ]]; then  # 4GB in KB
        log_warn "메모리가 4GB 미만입니다. 성능에 영향을 줄 수 있습니다."
    fi
    
    # 인터넷 연결 확인
    if ! ping -c 1 google.com &> /dev/null; then
        log_error "인터넷 연결을 확인해주세요."
        exit 1
    fi
    
    log_info "시스템 요구사항 확인 완료"
}

# 패키지 시스템 업데이트
update_package_system() {
    log_step "2" "패키지 시스템 업데이트 중..."
    
    # APT 소스 백업
    cp /etc/apt/sources.list /etc/apt/sources.list.backup.drakvuf
    
    # 패키지 목록 업데이트
    apt-get update 2>&1 | tee -a "$INSTALL_LOG"
    
    # deb-src 추가 (Ubuntu 24.04 noble)
    if ! grep -q "deb-src" /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null; then
        log_info "deb-src 저장소 활성화 중..."
        sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true
        apt-get update 2>&1 | tee -a "$INSTALL_LOG"
    fi
    
    log_info "패키지 시스템 업데이트 완료"
}

# 의존성 패키지 설치
install_dependencies() {
    log_step "3" "의존성 패키지 설치 중..."
    
    # 기본 도구 설치
    BASIC_PACKAGES="lsb-release patch build-essential git wget curl cmake flex bison"
    DEVEL_PACKAGES="libjson-c-dev autoconf-archive clang python3-dev libsystemd-dev"
    SYSTEM_PACKAGES="nasm bc libx11-dev ninja-build python3-pip meson llvm lld zlib1g-dev python3-tomli"
    ADDITIONAL_PACKAGES="libgnutls28-dev python3-venv"
    
    log_info "기본 패키지 설치 중..."
    apt-get --quiet --yes install $BASIC_PACKAGES 2>&1 | tee -a "$INSTALL_LOG"
    
    log_info "개발 패키지 설치 중..."
    apt-get --quiet --yes install $DEVEL_PACKAGES 2>&1 | tee -a "$INSTALL_LOG"
    
    log_info "시스템 패키지 설치 중..."
    apt-get --quiet --yes install $SYSTEM_PACKAGES 2>&1 | tee -a "$INSTALL_LOG"
    
    log_info "추가 패키지 설치 중..."
    apt-get --quiet --yes install $ADDITIONAL_PACKAGES 2>&1 | tee -a "$INSTALL_LOG"
    
    # GCC-9 설치 (가능한 경우)
    if apt-cache show gcc-9 &>/dev/null; then
        log_info "GCC-9 설치 중..."
        apt-get --quiet --yes install gcc-9 2>&1 | tee -a "$INSTALL_LOG"
    fi
    
    # Xen 빌드 의존성 설치
    log_info "Xen 빌드 의존성 설치 중..."
    apt-get --quiet --yes build-dep xen 2>&1 | tee -a "$INSTALL_LOG"
    
    log_info "의존성 패키지 설치 완료"
}

# Go 언어 설치
install_golang() {
    log_step "4" "Go 언어 설치 중..."
    
    if [[ ! -d "/usr/local/go" ]]; then
        log_info "Go 1.21.6 다운로드 및 설치 중..."
        wget -q https://go.dev/dl/go1.21.6.linux-amd64.tar.gz -O /tmp/go1.21.6.linux-amd64.tar.gz
        tar -C /usr/local -xzf /tmp/go1.21.6.linux-amd64.tar.gz
        rm /tmp/go1.21.6.linux-amd64.tar.gz
    else
        log_info "Go가 이미 설치되어 있습니다."
    fi
    
    # PATH 설정
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/environment
    export PATH=$PATH:/usr/local/go/bin
    
    log_info "Go 언어 설치 완료"
}

# DRAKVUF 패키지 다운로드 및 설치
install_drakvuf_packages() {
    log_step "5" "DRAKVUF 패키지 다운로드 및 설치 중..."
    
    PACKAGE_DIR="/tmp/drakvuf_packages"
    mkdir -p "$PACKAGE_DIR"
    cd "$PACKAGE_DIR"
    
    # Ubuntu 24.04 (noble) 패키지 확인 및 다운로드
    log_info "최신 DRAKVUF 패키지 확인 중..."
    
    # GitHub API를 통해 최신 릴리스 확인
    LATEST_RELEASE=$(curl -s https://api.github.com/repos/tklengyel/drakvuf-builds/releases/latest)
    
    # Ubuntu noble 패키지 다운로드
    NOBLE_PACKAGES=$(echo "$LATEST_RELEASE" | grep -o 'https://[^"]*noble[^"]*\.deb' | head -10)
    
    if [[ -z "$NOBLE_PACKAGES" ]]; then
        log_warn "Ubuntu 24.04 (noble) 전용 패키지를 찾을 수 없습니다. 범용 패키지를 시도합니다."
        
        # Ubuntu 22.04 (jammy) 패키지로 대체 시도
        log_info "Ubuntu 22.04 (jammy) 패키지 다운로드 중..."
        wget -q "https://github.com/tklengyel/drakvuf/releases/download/1.0/ubuntu_jammy_drakvuf-bundle-1.0-git20221220221439+068b10f-1-generic.deb" || true
        wget -q "https://github.com/tklengyel/drakvuf/releases/download/1.0/ubuntu_jammy_xen-hypervisor-4.17.0-generic-amd64.deb" || true
    else
        log_info "Ubuntu 24.04 (noble) 패키지 다운로드 중..."
        for package in $NOBLE_PACKAGES; do
            log_info "다운로드 중: $(basename "$package")"
            wget -q "$package" || log_warn "패키지 다운로드 실패: $package"
        done
    fi
    
    # 다운로드된 패키지 확인
    DEB_COUNT=$(ls -1 *.deb 2>/dev/null | wc -l)
    if [[ $DEB_COUNT -eq 0 ]]; then
        log_error "DRAKVUF 패키지를 다운로드할 수 없습니다."
        return 1
    fi
    
    log_info "$DEB_COUNT 개의 패키지를 다운로드했습니다."
    
    # 기존 패키지 정리
    log_info "기존 Xen 및 DRAKVUF 패키지 제거 중..."
    apt-get --yes remove xen* libxen* drakvuf* 2>&1 | tee -a "$INSTALL_LOG" || true
    apt-get -f --yes install 2>&1 | tee -a "$INSTALL_LOG"
    
    # 의존성 사전 설치
    log_info "패키지 의존성 확인 및 설치 중..."
    for deb in *.deb; do
        if [[ -f "$deb" ]]; then
            log_info "의존성 확인: $deb"
            DEPS=$(dpkg -I "$deb" | grep "Depends:" | awk -F':' '{print $2}' | tr ',' '\n' | sed 's/[^a-zA-Z0-9.-]//g' | grep -v '^$')
            for dep in $DEPS; do
                if [[ -n "$dep" ]]; then
                    apt-get --quiet --yes install "$dep" 2>&1 | tee -a "$INSTALL_LOG" || true
                fi
            done
        fi
    done
    
    # Xen 패키지 먼저 설치
    XEN_PACKAGES=$(ls *xen*.deb 2>/dev/null | head -5)
    if [[ -n "$XEN_PACKAGES" ]]; then
        log_info "Xen 하이퍼바이저 패키지 설치 중..."
        dpkg -i $XEN_PACKAGES 2>&1 | tee -a "$INSTALL_LOG"
    fi
    
    # DRAKVUF 패키지 설치
    DRAKVUF_PACKAGES=$(ls *drakvuf*.deb 2>/dev/null | head -5)
    if [[ -n "$DRAKVUF_PACKAGES" ]]; then
        log_info "DRAKVUF 패키지 설치 중..."
        dpkg -i $DRAKVUF_PACKAGES 2>&1 | tee -a "$INSTALL_LOG"
    fi
    
    # 의존성 문제 해결
    apt-get -f --yes install 2>&1 | tee -a "$INSTALL_LOG"
    
    log_info "DRAKVUF 패키지 설치 완료"
}

# Volatility3 설치
install_volatility3() {
    log_step "6" "Volatility3 설치 중..."
    
    if [[ ! -d "/opt/volatility3" ]]; then
        log_info "Python 가상환경 생성 중..."
        python3 -m venv /opt/volatility3
    fi
    
    log_info "Volatility3 의존성 설치 중..."
    source /opt/volatility3/bin/activate
    pip3 install --upgrade pip 2>&1 | tee -a "$INSTALL_LOG"
    pip3 install wheel construct pefile setuptools 2>&1 | tee -a "$INSTALL_LOG"
    
    # Volatility3 소스 가져오기
    if [[ -d "/home/runner/work/drakvuf/drakvuf/volatility3" ]]; then
        cd /home/runner/work/drakvuf/drakvuf/volatility3
        python3 setup.py build 2>&1 | tee -a "$INSTALL_LOG" || true
        python3 -m pip install . 2>&1 | tee -a "$INSTALL_LOG" || true
    fi
    
    deactivate
    
    log_info "Volatility3 설치 완료"
}

# 설치 완료 및 검증
finalize_installation() {
    log_step "7" "설치 완료 및 검증 중..."
    
    # 시스템 정리
    apt-get autoremove -y 2>&1 | tee -a "$INSTALL_LOG"
    apt-get autoclean 2>&1 | tee -a "$INSTALL_LOG"
    
    # 설치 확인
    log_info "설치된 패키지 확인 중..."
    
    INSTALLED_PACKAGES=""
    if dpkg -l | grep -q drakvuf; then
        INSTALLED_PACKAGES="$INSTALLED_PACKAGES DRAKVUF"
    fi
    if dpkg -l | grep -q xen-hypervisor; then
        INSTALLED_PACKAGES="$INSTALLED_PACKAGES Xen"
    fi
    if [[ -d "/opt/volatility3" ]]; then
        INSTALLED_PACKAGES="$INSTALLED_PACKAGES Volatility3"
    fi
    
    log_info "설치된 구성요소: $INSTALLED_PACKAGES"
    
    # GRUB 업데이트
    log_info "GRUB 부트로더 업데이트 중..."
    update-grub 2>&1 | tee -a "$INSTALL_LOG" || log_warn "GRUB 업데이트 실패"
    
    # 설치 완료 메시지
    echo ""
    echo "============================================"
    echo "    DRAKVUF 설치가 완료되었습니다!"
    echo "============================================"
    echo ""
    echo "다음 단계:"
    echo "1. 시스템을 재부팅하세요"
    echo "2. GRUB 메뉴에서 Xen을 선택하세요"
    echo "3. 웹 UI를 시작하려면 다음 명령어를 실행하세요:"
    echo "   cd /home/runner/work/drakvuf/drakvuf"
    echo "   python3 web_ui/app.py"
    echo ""
    echo "로그 파일 위치:"
    echo "- 설치 로그: $INSTALL_LOG"
    echo "- 오류 로그: $ERROR_LOG"
    echo ""
    
    # 재부팅 확인
    read -p "지금 재부팅하시겠습니까? (y/n): " reboot_now
    if [[ "$reboot_now" == "y" ]]; then
        log_info "시스템 재부팅 중..."
        reboot
    fi
}

# 메인 설치 프로세스
main() {
    # 로그 파일 초기화
    echo "DRAKVUF 자동 설치 시작: $(date)" > "$INSTALL_LOG"
    echo "DRAKVUF 설치 오류 로그: $(date)" > "$ERROR_LOG"
    
    log_info "DRAKVUF 자동 설치 시스템 시작"
    log_info "Ubuntu 24.04 최적화 버전"
    
    check_system_requirements
    update_package_system
    install_dependencies
    install_golang
    install_drakvuf_packages
    install_volatility3
    finalize_installation
    
    log_info "설치 프로세스 완료"
}

# 도움말 표시
show_help() {
    cat << 'EOF'
DRAKVUF 자동 설치 스크립트 - Ubuntu 24.04 최적화

사용법:
  sudo ./install_ubuntu24_automated.sh [옵션]

옵션:
  -h, --help     이 도움말 표시
  --check-only   시스템 요구사항만 확인
  --clean        시스템 정리만 수행

예제:
  sudo ./install_ubuntu24_automated.sh
  sudo ./install_ubuntu24_automated.sh --check-only
  sudo ./install_ubuntu24_automated.sh --clean

로그 파일:
  /var/log/drakvuf_install.log - 설치 로그
  /var/log/drakvuf_errors.log  - 오류 로그

EOF
}

# 명령행 인수 처리
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    --check-only)
        check_system_requirements
        exit 0
        ;;
    --clean)
        cleanup_and_retry
        exit 0
        ;;
    "")
        main
        ;;
    *)
        echo "알 수 없는 옵션: $1"
        echo "도움말을 보려면 --help를 사용하세요."
        exit 1
        ;;
esac