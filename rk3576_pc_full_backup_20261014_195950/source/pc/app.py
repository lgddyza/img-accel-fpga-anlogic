"""RK3576 PC control station with telemetry and bounded network preview."""
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
    QPlainTextEdit, QFileDialog, QMessageBox, QSplitter, QStyle, QScrollArea, QLayout, QFrame, QToolButton)
from serial.tools import list_ports

from transport import SSHTransport, SerialTransport, DATA_DIR, default_key, provision_key
from dashboard import ResourcePie, RateBars
from telemetry import TelemetryRates
from video_preview import VideoPreview, tool_icon

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
        self.rates = TelemetryRates()
        self.history = []
        self.yolo_fps = None
        self.setWindowTitle('RK3576 视觉控制台 · HDMI 同源预览')
        self.resize(1480, 940)
        self.setMinimumSize(1180, 760)
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
        button.setIcon(tool_icon(self, icon))
        button.setMinimumHeight(34)
        button.clicked.connect(callback)
        return button

    def build_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)
        layout.setContentsMargins(18, 16, 18, 10)
        layout.setSpacing(12)
        top = QHBoxLayout()
        title = QLabel('RK VISION')
        title.setObjectName('title')
        top.addWidget(title)
        subtitle = QLabel('RK3576 视觉控制台')
        subtitle.setObjectName('subtitle')
        top.addWidget(subtitle)
        top.addStretch()
        self.link_label = QLabel('● 未连接')
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
        self.more_connection = QToolButton()
        self.more_connection.setCheckable(True)
        self.more_connection.setArrowType(Qt.ArrowType.DownArrow)
        self.more_connection.setToolTip('连接设置 / SSH 密钥')
        self.more_connection.setMinimumSize(28, 30)
        connection_layout.addWidget(self.more_connection, 0, 7)
        self.key_button = self.button('串口配置 SSH 密钥', QStyle.StandardPixmap.SP_FileDialogDetailedView, self.setup_key)
        self.key_button.setToolTip('通过已经登录 root 的串口安装本机专用 SSH 公钥')
        connection_layout.addWidget(self.key_button, 1, 0, 1, 2)
        self.key_path = QLineEdit(str(self.settings.value('key', str(DATA_DIR/'rk_host_rsa'))))
        self.key_path.setPlaceholderText('SSH 私钥文件')
        connection_layout.addWidget(self.key_path, 1, 2, 1, 4)
        choose = self.button('', QStyle.StandardPixmap.SP_DirOpenIcon, self.choose_key)
        choose.setToolTip('选择 SSH 私钥')
        connection_layout.addWidget(choose, 1, 6)
        def show_connection_settings(expanded):
            for field in (self.key_button, self.key_path, choose):
                field.setVisible(expanded)
            self.more_connection.setArrowType(Qt.ArrowType.UpArrow if expanded else Qt.ArrowType.DownArrow)
        self.more_connection.toggled.connect(show_connection_settings)
        show_connection_settings(False)
        layout.addWidget(connection)
        splitter = QSplitter(Qt.Orientation.Horizontal)
        controls = QWidget()
        controls_layout = QVBoxLayout(controls)
        controls_layout.setContentsMargins(0, 0, 10, 0)
        controls_layout.setSizeConstraint(QLayout.SizeConstraint.SetMinimumSize)
        controls.setMinimumWidth(260)
        controls.setMaximumWidth(295)
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
        radios = QGridLayout()
        for i, name in enumerate(('灰度', '高斯', 'Sobel', '黑帽')):
            radio = QRadioButton(name)
            self.base_group.addButton(radio, (0, 1, 4, 5)[i])
            radios.addWidget(radio, i//2, i%2)
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
        controls_scroll.setMinimumWidth(280)
        controls_scroll.setMaximumWidth(315)
        splitter.addWidget(controls_scroll)
        middle = QWidget()
        ml = QVBoxLayout(middle)
        ml.setContentsMargins(8, 0, 8, 0)
        self.preview = VideoPreview()
        self.preview.requested.connect(self.request_preview)
        ml.addWidget(self.preview, 4)
        resources = QGroupBox('RK 资源占用')
        resources_layout = QVBoxLayout(resources)
        ml.addWidget(resources)
        splitter.addWidget(middle)
        right = QWidget()
        right.setMinimumWidth(300)
        right.setMaximumWidth(370)
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
            metrics.addWidget(block, index//2, index%2)
            self.metrics[key] = value
        rl.addLayout(metrics)
        self.warning = QLabel('等待连接 RK')
        self.warning.setWordWrap(True)
        self.warning.setObjectName('warning')
        rl.addWidget(self.warning)
        tabs = QTabWidget()
        self.tabs = tabs
        overview = QWidget()
        overview_layout = QVBoxLayout(overview)
        overview_layout.setContentsMargins(8, 12, 8, 12)
        overview_layout.setSpacing(10)
        resource_heading = QHBoxLayout()
        resource_title = QLabel('RK 资源占用')
        resource_title.setObjectName('sectionTitle')
        resource_heading.addWidget(resource_title)
        resource_heading.addStretch()
        self.device_info = QLabel('RK3576 · 2GB')
        self.device_info.setObjectName('muted')
        resource_heading.addWidget(self.device_info)
        resources_layout.addLayout(resource_heading)
        resource_title.hide()
        resource_row = QHBoxLayout()
        resource_row.setSpacing(12)
        self.cpu_pie = ResourcePie('CPU', '#10b981', '按两次/proc/stat计数差分，100%表示全部CPU核心繁忙；iowait计入空闲。')
        self.memory_pie = ResourcePie('内存', '#38bdf8', '已用=MemTotal−MemAvailable；可回收缓存计入可用。')
        self.npu_pie = ResourcePie('NPU', '#818cf8', 'rknpu驱动采样的各核心负载平均值，可能与端到端YOLO吞吐不同。')
        for chart in (self.cpu_pie, self.memory_pie, self.npu_pie):
            resource_row.addWidget(chart, 1)
        resources_layout.addLayout(resource_row)
        separator = QFrame()
        separator.setFrameShape(QFrame.Shape.HLine)
        overview_layout.addWidget(separator)
        self.rate_bars = RateBars()
        overview_layout.addWidget(self.rate_bars)
        overview_layout.addStretch(1)
        footer = QVBoxLayout()
        self.thermal_label = QLabel('温度 —')
        self.gpu_label = QLabel('GPU —')
        self.network_label = QLabel('网口 —')
        for label in (self.thermal_label, self.gpu_label, self.network_label):
            label.setObjectName('muted')
            footer.addWidget(label)
        footer.addStretch()
        overview_layout.addLayout(footer)
        overview_scroll = QScrollArea()
        overview_scroll.setWidgetResizable(True)
        overview_scroll.setFrameShape(QScrollArea.Shape.NoFrame)
        overview_scroll.setWidget(overview)
        rl.addWidget(overview_scroll, 1)
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
        tabs.setMinimumHeight(150)
        tabs.setMaximumHeight(210)
        details = QToolButton()
        details.setText('实时参数 / 识别结果 / 日志')
        details.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextBesideIcon)
        details.setCheckable(True)
        details.setArrowType(Qt.ArrowType.RightArrow)
        details.toggled.connect(lambda expanded: (
            tabs.setVisible(expanded), details.setArrowType(
                Qt.ArrowType.DownArrow if expanded else Qt.ArrowType.RightArrow)))
        ml.addWidget(details)
        ml.addWidget(tabs)
        tabs.hide()
        export_row = QHBoxLayout()
        self.fresh_label = QLabel('尚无采样')
        self.fresh_label.setObjectName('muted')
        export_row.addWidget(self.fresh_label)
        export_row.addStretch()
        export_row.addWidget(self.button('导出记录', QStyle.StandardPixmap.SP_DialogSaveButton, self.export))
        rl.addLayout(export_row)
        splitter.addWidget(right)
        splitter.setSizes([285, 820, 335])
        splitter.setStretchFactor(1, 1)
        layout.addWidget(splitter, 1)
        self.connection_mode()
        self.statusBar().showMessage('YOLOv8n · 640×640 · RK3576 / 2GB')
        self.setStyleSheet('''
            QWidget { font-family: "Microsoft YaHei UI"; font-size: 12px; color: #e2e8f0; }
            QMainWindow, QDialog { background: #0f172a; }
            QLabel#title { font-family: "Segoe UI"; font-size: 23px; font-weight: 700; color: #38bdf8; }
            QLabel#subtitle { font-size: 13px; color: #94a3b8; padding-left: 8px; }
            QLabel#sectionTitle { font-size: 14px; font-weight: 600; }
            QLabel#metric { font-family: "Segoe UI"; font-size: 29px; font-weight: 600; color: #10b981; }
            QLabel#rateTotal { font-family: "Segoe UI"; font-size: 18px; font-weight: 600; color: #38bdf8; }
            QLabel#link { font-weight: 600; padding: 7px 11px; background: #273548; border-radius: 4px; }
            QLabel#muted { color: #94a3b8; font-size: 11px; }
            QLabel#warning { background: #1e293b; padding: 9px 12px; border-left: 3px solid #38bdf8; }
            QGroupBox { background: #1e293b; border: 1px solid #334155; border-radius: 5px;
                        margin-top: 10px; padding: 12px 10px 8px 10px; }
            QGroupBox::title { subcontrol-origin: margin; left: 10px; padding: 0 4px; color: #94a3b8; }
            QPushButton, QToolButton { background: #273548; border: 1px solid #334155; border-radius: 4px; padding: 6px 10px; }
            QPushButton:hover, QToolButton:hover { background: #334155; border-color: #38bdf8; }
            QPushButton:pressed { background: #0e7490; }
            QPushButton:disabled { color: #64748b; background: #172133; border-color: #273548; }
            QPushButton#primary { background: #164e46; color: #34d399; border-color: #10b981; }
            QPushButton#primary:hover { background: #166858; }
            QPushButton#primary:disabled { background: #172b2b; color: #64748b; border-color: #334155; }
            QLineEdit, QSpinBox, QDoubleSpinBox, QComboBox { background: #273548; border: 1px solid #334155;
                         border-radius: 3px; padding: 5px; min-height: 20px; selection-background-color: #0e7490; }
            QComboBox QAbstractItemView { background: #273548; color: #e2e8f0; selection-background-color: #0e7490; }
            QLineEdit:focus, QSpinBox:focus, QDoubleSpinBox:focus { border-color: #38bdf8; }
            QTableWidget { background: #1e293b; alternate-background-color: #233044; gridline-color: #334155; border: none; selection-background-color: #0e7490; }
            QHeaderView::section { background: #273548; border: none; padding: 6px; font-weight: 600; color: #94a3b8; }
            QTabWidget::pane { background: #1e293b; border: 1px solid #334155; }
            QTabBar::tab { padding: 8px 12px; background: #172133; color: #94a3b8; }
            QTabBar::tab:selected { background: #1e293b; color: #38bdf8; border-top: 2px solid #38bdf8; }
            QTabBar::tab:hover { color: #38bdf8; }
            QScrollArea, QScrollArea > QWidget > QWidget { background: transparent; }
            QFrame[frameShape="4"] { color: #334155; }
            QSplitter::handle { background: #334155; width: 1px; }
            QStatusBar { background: #172133; color: #94a3b8; }
            QPlainTextEdit { background: #1e293b; border: none; font-family: Consolas; font-size: 12px; }
            QRadioButton::indicator, QCheckBox::indicator { width: 13px; height: 13px; border: 1px solid #64748b; background: #172133; }
            QRadioButton::indicator { border-radius: 7px; }
            QRadioButton::indicator:checked, QCheckBox::indicator:checked { background: #38bdf8; border-color: #38bdf8; }
            QScrollBar:vertical { background: #172133; width: 9px; }
            QScrollBar::handle:vertical { background: #475569; min-height: 25px; border-radius: 3px; }
            QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
            QScrollBar::add-page:vertical, QScrollBar::sub-page:vertical { background: transparent; }
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
        self.preview.stop()
        self.send('start', {'runtime': runtime, 'interval': self.interval.value(),
                           'confidence': self.confidence.value(), 'connector': self.connector.value(),
                           'restart': restart})

    def selected_mode(self):
        base = self.base_group.checkedId()
        return base + 2 if self.clahe.isChecked() else base

    def on_connected(self, target):
        self.linked = True
        self.sync_controls = True
        self.link_label.setText('● 已连接 · '+target)
        self.link_label.setStyleSheet('color: #34d399; background: #164e46;')
        self.connect_button.setText('断开')
        self.log_event('已连接 '+target)
        self.update_enabled()

    def on_disconnected(self):
        self.preview.stop()
        self.linked = False
        self.link_label.setText('● 未连接')
        self.link_label.setStyleSheet('')
        self.connect_button.setText('连接')
        self.previous_ai = None
        self.rates.reset()
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
        self.preview.start_button.setEnabled(bool(enabled and fresh and self.kind.currentIndex() == 0
            and (self.last_status or {}).get('runtime') in ('video', 'ai') and not self.preview.receiver))
        self.connection_mode()

    def request_preview(self):
        self.send('preview')

    def on_completed(self, action, response):
        self.log_event(action+' 完成')
        if action == 'preview':
            self.preview.start(self.host.text().strip(), response)
        elif action == 'stop':
            self.preview.stop()
        elif action == 'provision':
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
        self.rates.reset()
        for chart in (self.cpu_pie, self.memory_pie, self.npu_pie):
            chart.set_value(None, '暂无有效采样')
        self.rate_bars.set_rates([None]*3, None)
        self.thermal_label.setText('温度 —')
        self.gpu_label.setText('GPU —')
        self.network_label.setText('网口 —')

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
        if self.preview.receiver and (status.get('viewer_pid') != (self.last_status or {}).get('viewer_pid')
                                      or status.get('runtime') == 'stopped'):
            self.preview.stop()
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
        if getattr(self, 'sync_controls', False):
            mode = fpga.get('mode_applied')
            if type(mode) is int and 0 <= mode <= 7:
                self.clahe.setChecked(mode in (2, 3, 6, 7))
                base = mode-2 if mode in (2, 3, 6, 7) else mode
                self.base_group.button(base).setChecked(True)
            if fpga.get('qf_applied') is not None:
                self.qf.setValue(fpga['qf_applied'])
            if 'interval' in status:
                self.interval.setValue(status['interval'])
            if 'confidence' in status:
                self.confidence.setValue(status['confidence'])
            if 'connector' in status:
                self.connector.setValue(status['connector'])
            self.sync_controls = False
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
        rates = self.rates.update(status)
        self.cpu_pie.set_value(rates['cpu_percent'], f"{len(status.get('cpu', {}).get('ticks', {}))-1} 核 · 总体占用"
                               if status.get('cpu') else '等待CPU采样')
        total_memory, used_memory = status.get('memory_total_mb', 0), status.get('memory_used_mb', 0)
        self.memory_pie.set_value(100*used_memory/total_memory if total_memory else None,
                                 f'{used_memory:.0f} / {total_memory:.0f} MB' if total_memory else '等待内存采样')
        self.npu_pie.set_value(status.get('npu_load_percent'),
                              f"{self.fmt(status.get('npu_mhz'), 0)} MHz · 驱动采样")
        self.rate_bars.set_rates(rates['pcie_mbps'], rates['pcie_total_mbps'])
        self.thermal_label.setText('最高温度 '+self.fmt(hottest)+' °C')
        self.gpu_label.setText('GPU '+self.fmt(status.get('gpu_load_percent'), 0)+'%')
        network = status.get('network_links', [])
        self.network_label.setText('网口 '+(' / '.join(f"{n['speed_mbps']} Mbps" for n in network) if network else '—'))
        self.device_info.setText(f"RK3576 · {total_memory/1024:.2f} GB" if total_memory else 'RK3576 · 2GB')
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
            ('CPU 总体占用 %', self.fmt(rates['cpu_percent'])),
            ('NPU 核心占用 %', ' / '.join(self.fmt(v, 0) for v in status.get('npu_core_load_percent', [])) or '—'),
            ('GPU 占用 %', self.fmt(status.get('gpu_load_percent'))),
            ('PCIe JPEG 有效载荷 Mbps', self.fmt(rates['pcie_total_mbps'])),
            ('查看器 PID', str(status.get('viewer_pid', '—'))),
        ]
        for i, tile in enumerate(fpga.get('tiles', [])):
            values.append((f"JPEG {'ABC'[i]} 已发送 / 最近 bytes", f"{tile['sent']} / {tile['bytes']}"))
        for i, rate in enumerate(rates['pcie_mbps']):
            values.append((f"PCIe 通道 {'ABC'[i]} Mbps", self.fmt(rate)))
        for name, percent in rates['cpu_cores'].items():
            values.append((f'{name.upper()} 占用 %', self.fmt(percent)))
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
                             'yolo_fps': self.yolo_fps, 'hdmi_fps': hdmi, 'resources': rates,
                             'preview': dict(self.preview.stats)})
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
        self.preview.stop()
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
    parser.add_argument('--preview', action='store_true', help='连接后启动网络视频预览')
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
            if len(window.history) >= (12 if args.preview else 4) and (not args.preview or window.preview.seen >= 5):
                window.grab().save(str(args.verify_output/'ui_live.png'))
                if window.preview.canvas.image is not None:
                    window.preview.canvas.image.save(str(args.verify_output/'preview.png'))
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
    if args.preview:
        requested = [False]
        def auto_preview(status):
            if not requested[0] and status.get('runtime') in ('video', 'ai'):
                requested[0] = True
                window.request_preview()
        window.worker.telemetry.connect(auto_preview)
    if args.demo:
        window.link_label.setText('演示模式 · 无硬件操作')
        window.warning.setText('演示模式 · 无硬件操作')
    return application.exec()


if __name__ == '__main__':
    raise SystemExit(main())
