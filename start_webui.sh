#!/bin/bash

#****************************************************************************#
# DRAKVUF 웹 UI 시작 스크립트                                                  #
# Ubuntu 24.04 최적화                                                        #
#****************************************************************************#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_UI_DIR="$SCRIPT_DIR/web_ui"

echo "DRAKVUF 웹 UI 시작 중..."

# Python 가상환경 확인 및 생성
if [ ! -d "$WEB_UI_DIR/venv" ]; then
    echo "Python 가상환경 생성 중..."
    python3 -m venv "$WEB_UI_DIR/venv"
fi

# 가상환경 활성화
source "$WEB_UI_DIR/venv/bin/activate"

# 필요한 패키지 설치
echo "필요한 Python 패키지 설치 중..."
pip install --upgrade pip
pip install -r "$WEB_UI_DIR/requirements.txt"

# 로그 디렉토리 생성
sudo mkdir -p /var/log
sudo touch /var/log/drakvuf_webui.log
sudo touch /var/log/drakvuf_install.log
sudo touch /var/log/drakvuf_errors.log
sudo chmod 666 /var/log/drakvuf_*.log

# 웹 UI 시작
echo "DRAKVUF 웹 UI 시작..."
echo "브라우저에서 http://localhost:5000 으로 접속하세요."

cd "$WEB_UI_DIR"
python3 app.py