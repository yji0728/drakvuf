#!/usr/bin/env python3

#****************************************************************************#
# DRAKVUF 웹 UI - Flask 기반 사용자 인터페이스                                    #
# Ubuntu 24.04 최적화, 실시간 모니터링, 설치 관리                               #
#****************************************************************************#

import os
import sys
import json
import logging
import subprocess
import threading
import time
import signal
from datetime import datetime
from pathlib import Path

from flask import Flask, render_template, request, jsonify, send_file, flash, redirect, url_for
from flask_socketio import SocketIO, emit
import psutil

# 상위 디렉토리의 tools를 임포트하기 위한 경로 설정
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'tools'))

app = Flask(__name__)
app.config['SECRET_KEY'] = 'drakvuf_web_ui_secret_key_2024'
socketio = SocketIO(app, cors_allowed_origins="*")

# 로깅 설정
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/drakvuf_webui.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# 전역 변수
drakvuf_process = None
installation_status = {
    'is_installing': False,
    'current_step': '',
    'progress': 0,
    'log_messages': []
}

class DrakvufManager:
    """DRAKVUF 프로세스 관리 클래스"""
    
    def __init__(self):
        self.process = None
        self.is_running = False
        self.config = {}
        
    def start_analysis(self, config):
        """분석 시작"""
        if self.is_running:
            return False, "DRAKVUF가 이미 실행 중입니다."
        
        try:
            # DRAKVUF 실행 명령어 구성
            cmd = ['drakvuf']
            
            # 기본 옵션들
            if config.get('domain'):
                cmd.extend(['-d', config['domain']])
            if config.get('rekall_profile'):
                cmd.extend(['-r', config['rekall_profile']])
            if config.get('output_format'):
                cmd.extend(['-o', config['output_format']])
            if config.get('plugins'):
                for plugin in config['plugins']:
                    cmd.extend(['-a', plugin])
            
            # 추가 옵션들
            if config.get('timeout'):
                cmd.extend(['-t', str(config['timeout'])])
            if config.get('injection_timeout'):
                cmd.extend(['-e', str(config['injection_timeout'])])
            if config.get('verbose'):
                cmd.append('-v')
            
            logger.info(f"DRAKVUF 실행 명령어: {' '.join(cmd)}")
            
            # 프로세스 시작
            self.process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True
            )
            
            self.is_running = True
            self.config = config
            
            # 백그라운드에서 출력 모니터링
            threading.Thread(target=self._monitor_output, daemon=True).start()
            
            return True, "DRAKVUF 분석이 시작되었습니다."
            
        except Exception as e:
            logger.error(f"DRAKVUF 시작 실패: {e}")
            return False, f"분석 시작 실패: {str(e)}"
    
    def stop_analysis(self):
        """분석 중지"""
        if not self.is_running or not self.process:
            return False, "실행 중인 DRAKVUF 프로세스가 없습니다."
        
        try:
            self.process.terminate()
            self.process.wait(timeout=10)
            self.is_running = False
            return True, "DRAKVUF 분석이 중지되었습니다."
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.is_running = False
            return True, "DRAKVUF 프로세스가 강제 종료되었습니다."
        except Exception as e:
            logger.error(f"DRAKVUF 중지 실패: {e}")
            return False, f"분석 중지 실패: {str(e)}"
    
    def get_status(self):
        """현재 상태 반환"""
        return {
            'is_running': self.is_running,
            'process_id': self.process.pid if self.process else None,
            'config': self.config
        }
    
    def _monitor_output(self):
        """DRAKVUF 출력 모니터링"""
        if not self.process:
            return
        
        try:
            for line in iter(self.process.stdout.readline, ''):
                if line:
                    # WebSocket을 통해 실시간 출력 전송
                    socketio.emit('drakvuf_output', {'data': line.strip()})
                    logger.info(f"DRAKVUF 출력: {line.strip()}")
                
                if self.process.poll() is not None:
                    break
                    
        except Exception as e:
            logger.error(f"출력 모니터링 오류: {e}")
        finally:
            self.is_running = False
            socketio.emit('drakvuf_stopped', {'message': 'DRAKVUF 프로세스가 종료되었습니다.'})

# 전역 DRAKVUF 매니저 인스턴스
drakvuf_manager = DrakvufManager()

@app.route('/')
def index():
    """메인 페이지"""
    return render_template('index.html')

@app.route('/installation')
def installation():
    """설치 페이지"""
    return render_template('installation.html')

@app.route('/monitoring')
def monitoring():
    """모니터링 페이지"""
    return render_template('monitoring.html')

@app.route('/configuration')
def configuration():
    """설정 페이지"""
    return render_template('configuration.html')

@app.route('/logs')
def logs():
    """로그 페이지"""
    return render_template('logs.html')

# API 엔드포인트들

@app.route('/api/system/status')
def api_system_status():
    """시스템 상태 API"""
    try:
        # CPU 사용률
        cpu_percent = psutil.cpu_percent(interval=1)
        
        # 메모리 사용률
        memory = psutil.virtual_memory()
        
        # 디스크 사용률
        disk = psutil.disk_usage('/')
        
        # 시스템 정보
        uptime = datetime.now() - datetime.fromtimestamp(psutil.boot_time())
        
        # DRAKVUF 설치 확인
        drakvuf_installed = os.path.exists('/usr/bin/drakvuf') or os.path.exists('/usr/local/bin/drakvuf')
        
        # Xen 하이퍼바이저 확인
        xen_installed = os.path.exists('/usr/sbin/xl') or os.path.exists('/usr/bin/xl')
        
        return jsonify({
            'cpu_percent': cpu_percent,
            'memory': {
                'total': memory.total,
                'used': memory.used,
                'percent': memory.percent
            },
            'disk': {
                'total': disk.total,
                'used': disk.used,
                'percent': (disk.used / disk.total) * 100
            },
            'uptime': str(uptime).split('.')[0],
            'drakvuf_installed': drakvuf_installed,
            'xen_installed': xen_installed,
            'drakvuf_status': drakvuf_manager.get_status()
        })
    except Exception as e:
        logger.error(f"시스템 상태 조회 실패: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/installation/start', methods=['POST'])
def api_installation_start():
    """설치 시작 API"""
    global installation_status
    
    if installation_status['is_installing']:
        return jsonify({'error': '설치가 이미 진행 중입니다.'}), 400
    
    try:
        installation_status = {
            'is_installing': True,
            'current_step': '설치 준비 중...',
            'progress': 0,
            'log_messages': []
        }
        
        # 백그라운드에서 설치 실행
        threading.Thread(target=run_installation, daemon=True).start()
        
        return jsonify({'message': '설치가 시작되었습니다.'})
    except Exception as e:
        logger.error(f"설치 시작 실패: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/installation/status')
def api_installation_status():
    """설치 상태 API"""
    return jsonify(installation_status)

@app.route('/api/drakvuf/start', methods=['POST'])
def api_drakvuf_start():
    """DRAKVUF 시작 API"""
    config = request.json or {}
    
    success, message = drakvuf_manager.start_analysis(config)
    
    if success:
        return jsonify({'message': message})
    else:
        return jsonify({'error': message}), 500

@app.route('/api/drakvuf/stop', methods=['POST'])
def api_drakvuf_stop():
    """DRAKVUF 중지 API"""
    success, message = drakvuf_manager.stop_analysis()
    
    if success:
        return jsonify({'message': message})
    else:
        return jsonify({'error': message}), 500

@app.route('/api/drakvuf/status')
def api_drakvuf_status():
    """DRAKVUF 상태 API"""
    return jsonify(drakvuf_manager.get_status())

@app.route('/api/logs/system')
def api_logs_system():
    """시스템 로그 API"""
    try:
        logs = []
        log_files = [
            '/var/log/drakvuf_install.log',
            '/var/log/drakvuf_errors.log',
            '/var/log/drakvuf_webui.log'
        ]
        
        for log_file in log_files:
            if os.path.exists(log_file):
                with open(log_file, 'r') as f:
                    lines = f.readlines()[-100:]  # 최근 100줄만
                    logs.append({
                        'file': os.path.basename(log_file),
                        'lines': [line.strip() for line in lines]
                    })
        
        return jsonify({'logs': logs})
    except Exception as e:
        logger.error(f"로그 조회 실패: {e}")
        return jsonify({'error': str(e)}), 500

def run_installation():
    """설치 실행 함수"""
    global installation_status
    
    try:
        install_script = '/home/runner/work/drakvuf/drakvuf/scripts/install_ubuntu24_automated.sh'
        
        if not os.path.exists(install_script):
            installation_status['log_messages'].append('설치 스크립트를 찾을 수 없습니다.')
            installation_status['is_installing'] = False
            return
        
        # 설치 스크립트 실행
        process = subprocess.Popen(
            ['sudo', install_script],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True
        )
        
        installation_status['current_step'] = '설치 스크립트 실행 중...'
        installation_status['progress'] = 10
        
        # 출력 실시간 모니터링
        for line in iter(process.stdout.readline, ''):
            if line:
                line = line.strip()
                installation_status['log_messages'].append(line)
                
                # 진행률 업데이트 (간단한 휴리스틱)
                if 'STEP 1' in line:
                    installation_status['progress'] = 20
                elif 'STEP 2' in line:
                    installation_status['progress'] = 30
                elif 'STEP 3' in line:
                    installation_status['progress'] = 50
                elif 'STEP 4' in line:
                    installation_status['progress'] = 60
                elif 'STEP 5' in line:
                    installation_status['progress'] = 80
                elif 'STEP 6' in line:
                    installation_status['progress'] = 90
                elif 'STEP 7' in line:
                    installation_status['progress'] = 95
                elif '설치가 완료되었습니다' in line:
                    installation_status['progress'] = 100
                
                # WebSocket으로 실시간 업데이트
                socketio.emit('installation_update', installation_status)
                
                # 로그 메시지 개수 제한 (메모리 절약)
                if len(installation_status['log_messages']) > 1000:
                    installation_status['log_messages'] = installation_status['log_messages'][-500:]
        
        process.wait()
        
        if process.returncode == 0:
            installation_status['current_step'] = '설치 완료'
            installation_status['progress'] = 100
        else:
            installation_status['current_step'] = '설치 실패'
            installation_status['log_messages'].append(f'설치 프로세스가 오류 코드 {process.returncode}로 종료되었습니다.')
        
    except Exception as e:
        logger.error(f"설치 실행 오류: {e}")
        installation_status['current_step'] = '설치 오류'
        installation_status['log_messages'].append(f'오류: {str(e)}')
    finally:
        installation_status['is_installing'] = False
        socketio.emit('installation_update', installation_status)

# WebSocket 이벤트 핸들러들

@socketio.on('connect')
def handle_connect():
    """클라이언트 연결 시"""
    emit('connected', {'message': 'DRAKVUF 웹 UI에 연결되었습니다.'})

@socketio.on('disconnect')
def handle_disconnect():
    """클라이언트 연결 해제 시"""
    logger.info('클라이언트 연결 해제됨')

@socketio.on('request_system_status')
def handle_system_status():
    """시스템 상태 요청"""
    try:
        response = api_system_status()
        emit('system_status_update', response.json)
    except Exception as e:
        emit('error', {'message': f'시스템 상태 조회 실패: {str(e)}'})

# 시그널 핸들러
def signal_handler(sig, frame):
    """시그널 처리"""
    logger.info(f'시그널 {sig} 수신됨. 정리 중...')
    
    # DRAKVUF 프로세스 중지
    if drakvuf_manager.is_running:
        drakvuf_manager.stop_analysis()
    
    sys.exit(0)

if __name__ == '__main__':
    # 시그널 핸들러 등록
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    logger.info("DRAKVUF 웹 UI 서버 시작")
    
    # 개발 환경에서는 debug=True, 운영 환경에서는 False
    debug_mode = os.environ.get('FLASK_DEBUG', 'False').lower() == 'true'
    
    # 서버 시작
    socketio.run(
        app,
        host='0.0.0.0',
        port=5000,
        debug=debug_mode,
        allow_unsafe_werkzeug=True
    )