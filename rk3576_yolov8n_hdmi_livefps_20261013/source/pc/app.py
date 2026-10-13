"""RK3576 PC control station. HDMI stays on RK; telemetry travels over SSH/UART."""
import argparse
import json
from pathlib import Path
import queue
import threading
import time

from PySide6.QtCore import Qt, QThread, Signal, QTimer, QSettings
from PySide6.QtGui import QFont
from PySide6.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout,
    QHBoxLayout, QGridLayout, QFormLayout, QLabel, QPushButton, QComboBox,
    QLineEdit, QSpinBox, QDoubleSpinBox, QCheckBox, QRadioButton, QButtonGroup,
    QGroupBox, QTabWidget, QTableWidget, QTableWidgetItem, QHeaderView,
    QPlainTextEdit, QFileDialog, QMessageBox, QSplitter, QStyle, QScrollArea, QLayout)
from serial.tools import list_ports

from transport import SSHTransport, SerialTransport, DATA_DIR, default_key, provision_key

MODE_NAMES = ('灰度', '高斯', 'CLAHE', '高斯 + CLAHE', 'Sobel', '黑帽',
              'Sobel + CLAHE', '黑帽 + CLAHE')


class Worker(QThread):
    connected = Signal(str)
    disconnected = Signal()
    telemetry = Signal(dict)
    completed = Signal(str, dict)
    error = Signal(str, str)
    busy = Signal(bool)

    def __init__(self):
        super().__init__()
        self.tasks = queue.Queue(maxsize=8)
        self.stopping = threading.Event()
        self.connection = None

    def submit(self, action, payload=None):
        try:
            self.tasks.put_nowait((action, payload or {}))
        except queue.Full:
            self.error.emit(action, '操作队列已满，请等待当前操作完成')

    def close_connection(self):
        if self.connection:
            self.connection.close()
            self.connection = None
        self.disconnected.emit()

    def run(self):
        next_poll, failures = 0, 0
        try:
            while not self.stopping.is_set():
                try:
                    action, options = self.tasks.get(timeout=.1)
                except queue.Empty:
                    action = None
                if action:
                    self.busy.emit(True)
                    try:
                        if action == 'connect':
                            self.close_connection()
                            self.connection = (SSHTransport(options) if options['kind'] == 'ssh'
                                               else SerialTransport(options))
                            self.connection.install()
                            status = self.connection.rpc({'action': 'status'})
                            self.connected.emit(options['host'] if options['kind'] == 'ssh' else options['port'])
                            self.telemetry.emit(status)
                            failures = 0
                        elif action == 'disconnect':
                            self.close_connection()
                        elif action == 'provision':
                            self.close_connection()
                            provision_key(options['port'], options['baud'])
                            self.completed.emit(action, {})
                        elif self.connection:
                            response = self.connection.rpc(dict(options, action=action))
                            self.completed.emit(action, response)
                            if action in ('start', 'stop'):
                                self.telemetry.emit(response.get('status', response))
                        else:
                            raise RuntimeError('尚未连接 RK')
                    except Exception as exc:
                        self.error.emit(action, str(exc))
                        if action == 'connect':
                            self.close_connection()
                    finally:
                        self.busy.emit(False)
                        next_poll = time.monotonic()+1
                if self.connection and time.monotonic() >= next_poll:
                    try:
                        self.telemetry.emit(self.connection.rpc({'action': 'status'}))
                        failures = 0
                    except Exception as exc:
                        failures += 1
                        self.error.emit('poll', str(exc))
                        if failures >= 3:
                            self.close_connection()
                    next_poll = time.monotonic()+1
        finally:
            self.close_connection()


class Window(QMainWindow):
    def __init__(self, demo=False):
        super().__init__()
        self.demo = demo
        self.settings = QSettings('RKVision', 'PCStation')
        self.worker = Worker()
        self.linked = False
        self.operation_busy = False
        self.last_status = None
        self.last_received = 0
        self.previous_ai = None
        self.history = []
        self.yolo_fps = None
        self.setWindowTitle('RK3576 视觉控制台')
        self.resize(1240, 860)
        self.setMinimumSize(1000, 700)
        self.build_ui()
        self.worker.connected.connect(self.on_connected)
        self.worker.disconnected.connect(self.on_disconnected)
        self.worker.telemetry.connect(self.update_status)
        self.worker.completed.connect(self.on_completed)
        self.worker.error.connect(self.on_error)
        self.worker.busy.connect(self.set_busy)
        if not demo:
            self.worker.start()
        self.health_timer = QTimer(self)
        self.health_timer.timeout.connect(self.check_stale)
        self.health_timer.start(500)
        self.update_enabled()

    def button(self, text, icon, callback):
        button = QPushButton(text)
        button.setIcon(self.style().standardIcon(icon))
        button.setMinimumHeight(34)
        button.clicked.connect(callback)
        return button

    def build_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)
        layout.setContentsMargins(20, 16, 20, 12)
        layout.setSpacing(12)
        top = QHBoxLayout()
        title = QLabel('RK3576 / 视觉控制台')
        title.setObjectName('title')
        top.addWidget(title)
        top.addStretch()
        self.link_label = QLabel('未连接')
        self.link_label.setObjectName('link')
        top.addWidget(self.link_label)
        layout.addLayout(top)
        connection = QGroupBox('连接')
        connection_layout = QGridLayout(connection)
        self.kind = QComboBox()
        self.kind.addItems(['网线 / SSH', '串口 / UART'])
        self.kind.currentIndexChanged.connect(self.connection_mode)
        connection_layout.addWidget(self.kind, 0, 0)
        self.host = QLineEdit(str(self.settings.value('host', '169.254.53.76')))
        self.host.setPlaceholderText('RK IP 地址')
        connection_layout.addWidget(self.host, 0, 1)
        self.username = QLineEdit(str(self.settings.value('username', 'root')))
        self.username.setMaximumWidth(110)
        self.username.setPlaceholderText('SSH 用户')
        connection_layout.addWidget(self.username, 0, 2)
        self.password = QLineEdit()
        self.password.setEchoMode(QLineEdit.EchoMode.Password)
        self.password.setPlaceholderText('密码（留空使用密钥）')
        connection_layout.addWidget(self.password, 0, 3)
        self.port = QComboBox()
        self.port.setEditable(True)
        self.refresh_ports()
        self.port.setCurrentText(str(self.settings.value('port', 'COM12')))
        connection_layout.addWidget(self.port, 0, 4)
        self.baud = QComboBox()
        self.baud.addItems(['1500000', '115200', '921600'])
        connection_layout.addWidget(self.baud, 0, 5)
        self.connect_button = self.button('连接', QStyle.StandardPixmap.SP_DialogApplyButton, self.toggle_connect)
        connection_layout.addWidget(self.connect_button, 0, 6)
        self.key_button = self.button('串口配置 SSH 密钥', QStyle.StandardPixmap.SP_FileDialogDetailedView, self.setup_key)
        self.key_button.setToolTip('通过已经登录 root 的串口安装本机专用 SSH 公钥')
        connection_layout.addWidget(self.key_button, 1, 0, 1, 2)
        self.key_path = QLineEdit(str(self.settings.value('key', str(DATA_DIR/'rk_host_rsa'))))
        self.key_path.setPlaceholderText('SSH 私钥文件')
        connection_layout.addWidget(self.key_path, 1, 2, 1, 4)
        choose = self.button('', QStyle.StandardPixmap.SP_DirOpenIcon, self.choose_key)
        choose.setToolTip('选择 SSH 私钥')
        connection_layout.addWidget(choose, 1, 6)
        layout.addWidget(connection)
        splitter = QSplitter(Qt.Orientation.Horizontal)
        controls = QWidget()
        controls_layout = QVBoxLayout(controls)
        controls_layout.setContentsMargins(0, 0, 8, 0)
        controls_layout.setSizeConstraint(QLayout.SizeConstraint.SetMinimumSize)
        controls.setMinimumWidth(300)
        controls.setMaximumWidth(385)
        run = QGroupBox('HDMI 与 RK 推理')
        run_layout = QVBoxLayout(run)
        self.runtime_label = QLabel('运行状态：未知')
        run_layout.addWidget(self.runtime_label)
        self.initialize_button = self.button('初始化 PCIe / 驱动', QStyle.StandardPixmap.SP_BrowserReload,
                                             lambda: self.send('initialize'))
        self.video_button = self.button('仅显示 · 关闭 YOLO', QStyle.StandardPixmap.SP_ComputerIcon,
                                       lambda: self.start_runtime('video'))
        self.ai_button = self.button('显示 + YOLO', QStyle.StandardPixmap.SP_MediaPlay,
                                    lambda: self.start_runtime('ai'))
        self.ai_button.setObjectName('primary')
        self.stop_button = self.button('停止输出', QStyle.StandardPixmap.SP_MediaStop,
                                      lambda: self.send('stop'))
        for button in (self.initialize_button, self.video_button, self.ai_button, self.stop_button):
            run_layout.addWidget(button)
        controls_layout.addWidget(run)
        preprocessing = QGroupBox('FPGA 预处理')
        pl = QVBoxLayout(preprocessing)
        self.base_group = QButtonGroup(self)
        radios = QHBoxLayout()
        for i, name in enumerate(('灰度', '高斯', 'Sobel', '黑帽')):
            radio = QRadioButton(name)
            self.base_group.addButton(radio, (0, 1, 4, 5)[i])
            radios.addWidget(radio)
            if i == 1:
                radio.setChecked(True)
        pl.addLayout(radios)
        self.clahe = QCheckBox('增强后叠加 CLAHE')
        self.clahe.setChecked(True)
        pl.addWidget(self.clahe)
        self.apply_mode = self.button('应用预处理', QStyle.StandardPixmap.SP_DialogApplyButton,
                                      lambda: self.send('set_fpga', {'mode': self.selected_mode()}))
        pl.addWidget(self.apply_mode)
        self.applied_label = QLabel('请求 / 生效：— / —')
        self.applied_label.setWordWrap(True)
        pl.addWidget(self.applied_label)
        constants = QLabel('Sobel：3×3 / gain 0.5\n黑帽：3×3 / gain 1 / 方向滤波 line5')
        constants.setObjectName('muted')
        pl.addWidget(constants)
        controls_layout.addWidget(preprocessing)
        params = QGroupBox('运行参数')
        form = QFormLayout(params)
        qf_row = QHBoxLayout()
        self.qf = QSpinBox()
        self.qf.setRange(1, 100)
        self.qf.setValue(90)
        self.apply_qf = self.button('', QStyle.StandardPixmap.SP_DialogApplyButton,
                                    lambda: self.send('set_fpga', {'qf': self.qf.value()}))
        self.apply_qf.setToolTip('在线应用 JPEG QF')
        qf_row.addWidget(self.qf)
        qf_row.addWidget(self.apply_qf)
        form.addRow('JPEG QF', qf_row)
        self.confidence = QDoubleSpinBox()
        self.confidence.setDecimals(2)
        self.confidence.setRange(0, 1)
        self.confidence.setSingleStep(.01)
        self.confidence.setValue(.10)
        form.addRow('置信度', self.confidence)
        self.interval = QSpinBox()
        self.interval.setRange(1, 120)
        self.interval.setValue(2)
        form.addRow('每 N 帧推理', self.interval)
        self.connector = QSpinBox()
        self.connector.setRange(1, 10000)
        self.connector.setValue(188)
        form.addRow('HDMI connector', self.connector)
        self.restart_button = self.button('应用并重启 YOLO', QStyle.StandardPixmap.SP_BrowserReload,
                                          lambda: self.start_runtime('ai', restart=True))
        form.addRow(self.restart_button)
        self.applied_ai = QLabel('当前推理：—')
        self.applied_ai.setWordWrap(True)
        form.addRow(self.applied_ai)
        controls_layout.addWidget(params)
        controls_layout.addStretch()
        controls_scroll = QScrollArea()
        controls_scroll.setFrameShape(QScrollArea.Shape.NoFrame)
        controls_scroll.setWidgetResizable(True)
        controls_scroll.setWidget(controls)
        controls_scroll.setMinimumWidth(320)
        controls_scroll.setMaximumWidth(405)
        splitter.addWidget(controls_scroll)
        right = QWidget()
        rl = QVBoxLayout(right)
        rl.setContentsMargins(8, 0, 0, 0)
        metrics = QGridLayout()
        self.metrics = {}
        for index, (key, title) in enumerate((('hdmi', 'HDMI 实测 FPS'), ('yolo', 'YOLO 实时 FPS'),
                                            ('recon', '重建平均 FPS'), ('boxes', '当前检测框'))):
            block = QGroupBox(title)
            value = QLabel('—')
            value.setObjectName('metric')
            value.setMinimumHeight(44)
            value.setAlignment(Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter)
            box_layout = QVBoxLayout(block)
            box_layout.addWidget(value)
            metrics.addWidget(block, 0, index)
            self.metrics[key] = value
        rl.addLayout(metrics)
        self.warning = QLabel('等待连接 RK')
        self.warning.setWordWrap(True)
        self.warning.setObjectName('warning')
        rl.addWidget(self.warning)
        tabs = QTabWidget()
        self.params_table = QTableWidget(0, 2)
        self.params_table.setHorizontalHeaderLabels(['状态项', '实际值'])
        self.setup_table(self.params_table)
        tabs.addTab(self.params_table, '实时参数')
        self.boxes_table = QTableWidget(0, 6)
        self.boxes_table.setHorizontalHeaderLabels(['标签', '置信度', 'x1', 'y1', 'x2', 'y2'])
        self.setup_table(self.boxes_table)
        tabs.addTab(self.boxes_table, '识别结果')
        self.remote_log = QPlainTextEdit()
        self.remote_log.setReadOnly(True)
        tabs.addTab(self.remote_log, 'RK 日志')
        self.events = QPlainTextEdit()
        self.events.setReadOnly(True)
        self.events.setMaximumBlockCount(1000)
        tabs.addTab(self.events, '操作记录')
        rl.addWidget(tabs, 1)
        export_row = QHBoxLayout()
        self.fresh_label = QLabel('尚无采样')
        self.fresh_label.setObjectName('muted')
        export_row.addWidget(self.fresh_label)
        export_row.addStretch()
        export_row.addWidget(self.button('导出记录', QStyle.StandardPixmap.SP_DialogSaveButton, self.export))
        rl.addLayout(export_row)
        splitter.addWidget(right)
        splitter.setStretchFactor(1, 1)
        layout.addWidget(splitter, 1)
        self.connection_mode()
        self.statusBar().showMessage('YOLOv8n · 640×640 · RK3576 / 2GB')
        self.setStyleSheet('''
            QWidget { font-family: "Microsoft YaHei UI"; font-size: 12px; color: #252c32; }
            QMainWindow { background: #f4f6f7; }
            QLabel#title { font-size: 21px; font-weight: 600; }
            QLabel#metric { font-family: "Segoe UI"; font-size: 30px; font-weight: 600; color: #087c73; }
            QLabel#link { font-weight: 600; padding: 6px; }
            QLabel#muted { color: #647079; }
            QLabel#warning { background: #edf2f3; padding: 9px; border-left: 3px solid #819398; }
            QGroupBox { background: #ffffff; border: 1px solid #dce2e5; border-radius: 5px;
                        margin-top: 9px; padding: 12px 9px 6px 9px; }
            QGroupBox::title { subcontrol-origin: margin; left: 10px; padding: 0 4px; }
            QPushButton { background: #ffffff; border: 1px solid #cbd4d9; border-radius: 4px; padding: 5px 9px; }
            QPushButton:hover { background: #edf4f4; border-color: #589e99; }
            QPushButton:disabled { color: #98a2a8; background: #f3f5f6; }
            QPushButton#primary { background: #087c73; color: white; border-color: #087c73; }
            QPushButton#primary:disabled { background: #bacdca; border-color: #bacdca; }
            QLineEdit, QSpinBox, QDoubleSpinBox, QComboBox { background: white; border: 1px solid #cbd4d9;
                         border-radius: 3px; padding: 5px; min-height: 20px; }
            QTableWidget { background: #ffffff; gridline-color: #e7ecef; border: 1px solid #dce2e5; }
            QHeaderView::section { background: #edf1f3; border: none; padding: 8px; font-weight: 600; }
            QTabWidget::pane { border: 1px solid #dce2e5; }
            QTabBar::tab { padding: 9px 15px; background: #e8edef; }
            QTabBar::tab:selected { background: white; border-top: 2px solid #087c73; }
            QPlainTextEdit { background: #ffffff; border: none; font-family: Consolas; font-size: 12px; }
        ''')

    @staticmethod
    def setup_table(table):
        table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        table.setAlternatingRowColors(True)
        table.verticalHeader().hide()
        table.horizontalHeader().setSectionResizeMode(QHeaderView.ResizeMode.Stretch)
        table.horizontalHeader().setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)

    def refresh_ports(self):
        self.port.clear()
        self.port.addItems([p.device for p in list_ports.comports()])

    def connection_mode(self):
        ssh = self.kind.currentIndex() == 0
        for field in (self.host, self.username, self.password, self.key_path):
            field.setEnabled(ssh and not self.linked and not self.operation_busy)
        # UART fields also select the shell used by key provisioning.
        self.port.setEnabled(not self.linked and not self.operation_busy)
        self.baud.setEnabled(not self.linked and not self.operation_busy)

    def choose_key(self):
        path, _ = QFileDialog.getOpenFileName(self, '选择 SSH 私钥', str(DATA_DIR))
        if path:
            self.key_path.setText(path)

    def setup_key(self):
        self.worker.submit('provision', {'port': self.port.currentText(), 'baud': int(self.baud.currentText())})

    def toggle_connect(self):
        if self.linked:
            self.worker.submit('disconnect')
            return
        options = {'kind': 'ssh' if self.kind.currentIndex() == 0 else 'serial',
                   'host': self.host.text().strip(), 'username': self.username.text().strip(),
                   'password': self.password.text(), 'key': self.key_path.text().strip(),
                   'port': self.port.currentText(), 'baud': int(self.baud.currentText())}
        if options['kind'] == 'ssh' and not options['password'] and not Path(options['key']).is_file():
            self.on_error('connect', '未找到 SSH 私钥，请先用串口配置密钥，或填写密码')
            return
        for field in ('host', 'username', 'key', 'port'):
            self.settings.setValue(field, options[field])
        self.worker.submit('connect', options)

    def send(self, action, payload=None):
        self.log_event('提交 '+action + (' '+json.dumps(payload, ensure_ascii=False) if payload else ''))
        self.worker.submit(action, payload)

    def start_runtime(self, runtime, restart=False):
        self.send('start', {'runtime': runtime, 'interval': self.interval.value(),
                           'confidence': self.confidence.value(), 'connector': self.connector.value(),
                           'restart': restart})

    def selected_mode(self):
        base = self.base_group.checkedId()
        return base + 2 if self.clahe.isChecked() else base

    def on_connected(self, target):
        self.linked = True
        self.link_label.setText('已连接 · '+target)
        self.connect_button.setText('断开')
        self.log_event('已连接 '+target)
        self.update_enabled()

    def on_disconnected(self):
        self.linked = False
        self.link_label.setText('未连接')
        self.connect_button.setText('连接')
        self.previous_ai = None
        self.yolo_fps = None
        self.last_status = None
        self.last_received = 0
        self.clear_live()
        self.update_enabled()

    def set_busy(self, busy):
        self.operation_busy = busy
        self.update_enabled()
        if busy:
            self.statusBar().showMessage('正在执行 RK 操作…')
        else:
            self.statusBar().showMessage('YOLOv8n · 640×640 · RK3576 / 2GB')

    def update_enabled(self):
        enabled = self.linked and not self.operation_busy and not self.demo
        fresh = self.last_received and time.monotonic()-self.last_received < 6
        fpga_ok = enabled and fresh and bool((self.last_status or {}).get('fpga'))
        for button in (self.initialize_button, self.stop_button):
            button.setEnabled(enabled)
        for button in (self.video_button, self.ai_button, self.restart_button, self.apply_mode, self.apply_qf):
            button.setEnabled(bool(fpga_ok))
        self.connect_button.setEnabled(not self.operation_busy and not self.demo)
        self.key_button.setEnabled(not self.linked and not self.operation_busy and not self.demo)
        self.kind.setEnabled(not self.linked and not self.operation_busy)
        self.connection_mode()

    def on_completed(self, action, response):
        self.log_event(action+' 完成')
        if action == 'provision':
            self.key_path.setText(str(default_key()))
            self.kind.setCurrentIndex(0)
            self.warning.setText('SSH 密钥已配置，可连接网线地址')
        elif action in ('set_fpga', 'initialize'):
            self.warning.setText('参数已回读确认，等待下一次状态采样')

    def on_error(self, action, message):
        self.log_event(action+' 失败：'+message)
        self.warning.setText(message)
        if action == 'poll':
            self.clear_live()
        elif action != 'connect' or not self.demo:
            QMessageBox.warning(self, 'RK 操作未完成', message)

    def log_event(self, message):
        self.events.appendPlainText(time.strftime('%H:%M:%S')+'  '+message)

    def clear_live(self):
        for label in self.metrics.values():
            label.setText('—')
        self.boxes_table.setRowCount(0)
        self.params_table.setRowCount(0)
        self.runtime_label.setText('运行状态：未知')
        self.applied_label.setText('请求 / 生效：— / —')
        self.applied_ai.setText('当前推理：—')
        self.fresh_label.setText('状态未连接或已过期')

    def check_stale(self):
        if self.linked and self.last_received and time.monotonic()-self.last_received > 6:
            self.clear_live()
            self.warning.setText('状态已过期，等待 RK 响应；断开连接不会停止板端运行')
            self.update_enabled()

    @staticmethod
    def fmt(value, digits=1):
        return '—' if value is None else f'{value:.{digits}f}'

    @staticmethod
    def mode_name(value):
        return MODE_NAMES[value] if type(value) is int and 0 <= value < 8 else '未知'

    def update_status(self, status):
        self.last_status = status
        self.last_received = time.monotonic()
        runtime = status['runtime']
        self.runtime_label.setText('运行状态：'+{'ai': '显示 + YOLO', 'video': '仅显示', 'stopped': '已停止'}[runtime])
        ai = status.get('ai')
        if ai and ai['age_ms'] <= 2000:
            previous = self.previous_ai
            if previous and previous[0] == status['viewer_pid'] and ai['updated_us'] > previous[2]:
                delta = (ai['seq']-previous[1]) & 0xffffffff
                self.yolo_fps = delta/2/((ai['updated_us']-previous[2])/1e6) if delta < 10000 else None
            elif previous and ai['updated_us'] == previous[2]:
                self.yolo_fps = 0
            else:
                self.yolo_fps = None
            self.previous_ai = (status['viewer_pid'], ai['seq'], ai['updated_us'])
            boxes = ai['boxes']
        else:
            self.yolo_fps = 0 if runtime == 'ai' else None
            self.previous_ai = None
            boxes = []
        stats, fpga = status.get('stats', {}), status.get('fpga', {})
        hdmi = stats.get('hdmi_fps') if runtime != 'stopped' and stats.get('log_age_s', 99) < 3 else None
        self.metrics['hdmi'].setText(self.fmt(hdmi))
        self.metrics['yolo'].setText(self.fmt(self.yolo_fps))
        self.metrics['recon'].setText(self.fmt(stats.get('reconstructed_avg_fps')
                                             if stats.get('log_age_s', 99) < 6 else None))
        self.metrics['boxes'].setText(str(len(boxes)) if runtime == 'ai' else '—')
        self.applied_label.setText('请求 / 生效：'+self.mode_name(fpga.get('mode_requested'))+' / '+
                                   self.mode_name(fpga.get('mode_applied')))
        self.applied_ai.setText(f"当前推理：conf {status.get('confidence', '—')} / interval {status.get('interval', '—')}")
        bitmap = fpga.get('bitmap', 0)
        for button in self.base_group.buttons():
            button.setEnabled(bool(bitmap & (1 << self.base_group.id(button))))
        temperatures = status.get('temperatures', [])
        hottest = max((t['celsius'] for t in temperatures), default=None)
        values = [
            ('主机', status.get('hostname', '—')), ('FPGA ABI', fpga.get('tag', '—')),
            ('预处理请求', self.mode_name(fpga.get('mode_requested'))),
            ('预处理已生效', self.mode_name(fpga.get('mode_applied'))),
            ('QF 请求 / 生效', f"{fpga.get('qf_requested', '—')} / {fpga.get('qf_applied', '—')}"),
            ('输入帧率选择（标称）', str(fpga.get('input_fps', '—'))),
            ('HDMI 实测 FPS', self.fmt(hdmi)), ('YOLO 实时 FPS', self.fmt(self.yolo_fps)),
            ('推理平均耗时 ms', self.fmt(stats.get('ai_avg_ms'))),
            ('检测结果年龄 ms', self.fmt(ai.get('age_ms') if ai else None)),
            ('FPGA 预处理故障', str(fpga.get('preproc_fault', '—'))),
            ('JPEG 故障寄存器', str(fpga.get('jpeg_faults', '—'))),
            ('未配对分片（累计）', str(stats.get('unpaired', '—'))),
            ('显示队列拥塞（累计）', str(stats.get('queue_overruns', '—'))),
            ('内存 已用 / 总量 MB', f"{status['memory_used_mb']:.0f} / {status['memory_total_mb']:.0f}"),
            ('最高温度 °C', self.fmt(hottest)), ('NPU MHz', self.fmt(status.get('npu_mhz'), 0)),
            ('系统负载（1分钟）', self.fmt(status.get('load'), 2)),
            ('查看器 PID', str(status.get('viewer_pid', '—'))),
        ]
        for i, tile in enumerate(fpga.get('tiles', [])):
            values.append((f"JPEG {'ABC'[i]} 已发送 / 最近 bytes", f"{tile['sent']} / {tile['bytes']}"))
        self.params_table.setRowCount(len(values))
        for row, (key, value) in enumerate(values):
            self.params_table.setItem(row, 0, QTableWidgetItem(key))
            self.params_table.setItem(row, 1, QTableWidgetItem(value))
        self.boxes_table.setRowCount(len(boxes))
        for row, box in enumerate(boxes):
            values = [box['label'], f"{box['confidence']:.3f}"] + [f'{v:.0f}' for v in box['xyxy']]
            for col, text in enumerate(values):
                self.boxes_table.setItem(row, col, QTableWidgetItem(text))
        self.remote_log.setPlainText(status.get('log', ''))
        self.remote_log.verticalScrollBar().setValue(self.remote_log.verticalScrollBar().maximum())
        if status.get('fpga_error'):
            self.warning.setText('FPGA 未就绪：'+status['fpga_error'])
        elif fpga.get('preproc_fault') or fpga.get('jpeg_faults'):
            self.warning.setText('FPGA 报告故障，请检查 RK 日志与相机通路')
        elif runtime == 'ai' and (not ai or ai['age_ms'] > 2000):
            self.warning.setText('YOLO 进程存在，尚未收到新的有效推理结果')
        elif runtime == 'stopped':
            self.warning.setText('设备已连接，HDMI 输出已停止')
        else:
            self.warning.setText('状态正常 · '+self.mode_name(fpga.get('mode_applied')))
        if self.demo:
            self.warning.setText('演示数据 · 无硬件操作')
        self.fresh_label.setText(('演示数据 · ' if self.demo else '')+'最近采样 '+time.strftime('%H:%M:%S'))
        self.history.append({'pc_time': time.strftime('%Y-%m-%d %H:%M:%S'), 'status': status,
                             'yolo_fps': self.yolo_fps, 'hdmi_fps': hdmi})
        if len(self.history) > 10000:
            del self.history[:1000]
        self.update_enabled()

    def export(self):
        path, _ = QFileDialog.getSaveFileName(self, '导出运行记录',
                    'rk_session_'+time.strftime('%Y%m%d_%H%M%S')+'.json', 'JSON (*.json)')
        if path:
            Path(path).write_text(json.dumps({'samples': self.history, 'events': self.events.toPlainText()},
                                             indent=2, ensure_ascii=False), encoding='utf-8')
            self.log_event('记录已导出 '+path)

    def closeEvent(self, event):
        self.worker.stopping.set()
        # Wait for the serialized RPC to return before releasing its transport.
        if self.worker.isRunning() and not self.worker.wait(30000):
            event.ignore()
            self.warning.setText('正在等待 RK 操作结束，请稍后关闭')
            return
        event.accept()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--demo', action='store_true')
    parser.add_argument('--connect', action='store_true')
    parser.add_argument('--verify-output', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    application = QApplication([])
    application.setStyle('Fusion')
    application.setFont(QFont('Microsoft YaHei UI', 10))
    window = Window(demo=args.demo)
    window.show()
    if args.verify_output:
        args.verify_output.mkdir(parents=True, exist_ok=True)
        def finish_verification(status):
            if len(window.history) >= 4:
                window.grab().save(str(args.verify_output/'ui_live.png'))
                (args.verify_output/'exe_status.json').write_text(
                    json.dumps({'samples': window.history, 'events': window.events.toPlainText()}, indent=2),
                    encoding='utf-8')
                window.close()
                application.quit()
        def fail_verification(action, message):
            (args.verify_output/'exe_error.json').write_text(json.dumps({'action': action, 'error': message}),
                                                            encoding='utf-8')
            window.close()
            application.exit(1)
        window.worker.telemetry.connect(finish_verification)
        window.worker.error.disconnect(window.on_error)
        window.worker.error.connect(fail_verification)
        QTimer.singleShot(30000, lambda: fail_verification('timeout', 'UI verification timeout'))
    if args.connect:
        QTimer.singleShot(300, window.toggle_connect)
    if args.demo:
        window.link_label.setText('演示模式 · 无硬件操作')
        window.warning.setText('演示模式 · 无硬件操作')
    return application.exec()


if __name__ == '__main__':
    raise SystemExit(main())
