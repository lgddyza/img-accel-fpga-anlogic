"""MJPEG receiver with a single-frame mailbox and aspect-preserving Qt display."""
from email.parser import BytesHeaderParser
import http.client
import threading
import time

from PySide6.QtCore import Qt, QThread, Signal, QTimer
from PySide6.QtGui import QColor, QIcon, QImage, QPainter
from PySide6.QtWidgets import QWidget, QVBoxLayout, QHBoxLayout, QLabel, QPushButton, QDialog, QFileDialog, QStyle


def tool_icon(widget, standard):
    if standard not in (QStyle.StandardPixmap.SP_MediaPlay, QStyle.StandardPixmap.SP_MediaStop,
                        QStyle.StandardPixmap.SP_TitleBarMaxButton, QStyle.StandardPixmap.SP_TitleBarNormalButton):
        return widget.style().standardIcon(standard)
    pixmap = widget.style().standardIcon(standard).pixmap(18, 18)
    painter = QPainter(pixmap)
    painter.setCompositionMode(QPainter.CompositionMode.CompositionMode_SourceIn)
    painter.fillRect(pixmap.rect(), QColor('#cbd5e1'))
    painter.end()
    return QIcon(pixmap)


class Receiver(QThread):
    failed = Signal(str)

    def __init__(self, host, options):
        super().__init__()
        self.host, self.options = host, options
        self.stopping = threading.Event()
        self.lock = threading.Lock()
        self.latest = None
        self.sequence = 0
        self.received_bytes = 0
        self.connection = None
        self.started_at = time.monotonic()

    def stop(self):
        self.stopping.set()
        if self.connection and self.connection.sock:
            try:
                self.connection.sock.shutdown(2)
            except OSError:
                pass

    def run(self):
        try:
            self.connection = http.client.HTTPConnection(self.host, self.options['port'], timeout=5)
            self.connection.request('GET', '/stream', headers={'Authorization': 'Bearer '+self.options['token']})
            response = self.connection.getresponse()
            if response.status != 200:
                raise RuntimeError(f'视频连接被拒绝：HTTP {response.status}')
            while not self.stopping.is_set():
                line = response.readline(4096)
                if not line:
                    raise RuntimeError('RK 视频连接已关闭')
                if line.strip() != b'--rkframe':
                    continue
                header = bytearray()
                while True:
                    line = response.readline(4096)
                    if not line:
                        raise RuntimeError('视频帧头不完整')
                    header.extend(line)
                    if len(header) > 8192:
                        raise RuntimeError('视频帧头过长')
                    if line == b'\r\n':
                        break
                fields = BytesHeaderParser().parsebytes(bytes(header))
                size = int(fields['Content-Length'])
                if not 0 < size <= 4_000_000:
                    raise RuntimeError('视频帧长度异常')
                payload = response.read(size)
                if len(payload) != size:
                    raise RuntimeError('视频帧传输中断')
                frame = QImage.fromData(payload, 'JPEG')
                if frame.isNull():
                    raise RuntimeError('视频 JPEG 解码失败')
                with self.lock:
                    self.latest = frame
                    self.sequence += 1
                    self.received_bytes += size
        except Exception as exc:
            if not self.stopping.is_set():
                self.failed.emit(str(exc))
        finally:
            if self.connection:
                self.connection.close()


class Canvas(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.image = None
        self.message = '暂无视频信号'
        self.setMinimumSize(240, 135)

    def paintEvent(self, _event):
        painter = QPainter(self)
        painter.fillRect(self.rect(), QColor('#080f1c'))
        if self.image is not None:
            size = self.image.size().scaled(self.size(), Qt.AspectRatioMode.KeepAspectRatio)
            from PySide6.QtCore import QRect
            target = QRect((self.width()-size.width())//2, (self.height()-size.height())//2,
                           size.width(), size.height())
            painter.drawImage(target, self.image)
        else:
            painter.setPen(QColor('#94a3b8'))
            painter.drawText(self.rect().adjusted(15, 15, -15, -15),
                             Qt.AlignmentFlag.AlignCenter | Qt.TextFlag.TextWordWrap, self.message)


class VideoPreview(QWidget):
    requested = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.receiver = None
        self.fullscreen = None
        self.seen = 0
        self.last_count = 0
        self.last_bytes = 0
        self.last_sample = time.monotonic()
        self.last_frame = 0
        self.stats = {'fps': None, 'mbps': None, 'frames': 0}
        self.history = []
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        header = QHBoxLayout()
        title = QLabel('实时视频预览')
        title.setObjectName('sectionTitle')
        header.addWidget(title)
        header.addStretch()
        self.start_button = self.tool('开始', QStyle.StandardPixmap.SP_MediaPlay, self.requested.emit)
        self.stop_button = self.tool('停止', QStyle.StandardPixmap.SP_MediaStop, self.stop)
        self.snapshot_button = self.tool('', QStyle.StandardPixmap.SP_DialogSaveButton, self.snapshot)
        self.snapshot_button.setToolTip('保存当前预览帧')
        self.full_button = self.tool('', QStyle.StandardPixmap.SP_TitleBarMaxButton, self.open_fullscreen)
        self.full_button.setToolTip('全屏预览')
        for button in (self.start_button, self.stop_button, self.snapshot_button, self.full_button):
            header.addWidget(button)
        layout.addLayout(header)
        self.canvas = Canvas()
        layout.addWidget(self.canvas, 1)
        self.info = QLabel('MJPEG · 960 × 540 · 上限 15 FPS')
        self.info.setObjectName('muted')
        layout.addWidget(self.info)
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.refresh)
        self.timer.start(33)
        self.stop_button.setEnabled(False)
        self.snapshot_button.setEnabled(False)
        self.full_button.setEnabled(False)
        self.start_button.setEnabled(False)

    def tool(self, text, icon, callback):
        button = QPushButton(text)
        button.setIcon(tool_icon(self, icon))
        button.clicked.connect(callback)
        button.setMinimumHeight(30)
        return button

    def start(self, host, options):
        self.stop()
        self.canvas.image = None
        self.canvas.message = '正在连接 RK 视频…'
        self.canvas.update()
        self.seen = self.last_count = self.last_bytes = 0
        self.last_sample = time.monotonic()
        self.last_frame = self.last_sample
        self.receiver = Receiver(host, options)
        self.receiver.failed.connect(self.failed)
        self.receiver.start()
        self.stop_button.setEnabled(True)
        self.start_button.setEnabled(False)

    def stop(self):
        if self.receiver:
            self.receiver.failed.disconnect(self.failed)
            self.receiver.stop()
            self.receiver.wait(6500)
            self.receiver = None
        self.canvas.image = None
        self.canvas.message = '暂无视频信号'
        self.canvas.update()
        if self.fullscreen:
            self.fullscreen.close()
        self.stop_button.setEnabled(False)
        self.start_button.setEnabled(True)
        self.snapshot_button.setEnabled(False)
        self.full_button.setEnabled(False)
        self.info.setText('MJPEG · 960 × 540 · 上限 15 FPS')
        self.stats = {'fps': None, 'mbps': None, 'frames': 0}

    def failed(self, message):
        self.stop()
        self.canvas.message = message
        self.canvas.update()

    def refresh(self):
        if not self.receiver:
            return
        now = time.monotonic()
        with self.receiver.lock:
            count, byte_count, frame = self.receiver.sequence, self.receiver.received_bytes, self.receiver.latest
        if count != self.seen and frame is not None:
            self.seen = count
            self.last_frame = now
            self.canvas.image = frame
            self.canvas.update()
            if self.fullscreen:
                self.fullscreen.canvas.image = frame
                self.fullscreen.canvas.update()
            self.snapshot_button.setEnabled(True)
            self.full_button.setEnabled(True)
        if now-self.last_frame > 3:
            self.canvas.image = None
            self.canvas.message = '视频信号已过期'
            self.canvas.update()
            if self.fullscreen:
                self.fullscreen.canvas.image = None
                self.fullscreen.canvas.message = self.canvas.message
                self.fullscreen.canvas.update()
            self.snapshot_button.setEnabled(False)
            self.full_button.setEnabled(False)
        if now-self.last_sample >= 1:
            elapsed = now-self.last_sample
            self.stats = {'fps': (count-self.last_count)/elapsed,
                          'mbps': (byte_count-self.last_bytes)*8/elapsed/1e6, 'frames': count}
            self.history.append(dict(self.stats, pc_time=time.time()))
            self.history = self.history[-10000:]
            self.info.setText(f"LIVE · 960 × 540 · {self.stats['fps']:.1f} FPS · {self.stats['mbps']:.2f} Mbps")
            self.last_sample, self.last_count, self.last_bytes = now, count, byte_count

    def snapshot(self):
        if self.canvas.image is None:
            return
        path, _ = QFileDialog.getSaveFileName(self, '保存视频截图',
                    'rk_preview_'+time.strftime('%Y%m%d_%H%M%S')+'.png', 'PNG (*.png)')
        if path and not self.canvas.image.save(path):
            self.info.setText('截图保存失败')

    def open_fullscreen(self):
        if self.fullscreen:
            return
        dialog = QDialog(self)
        dialog.setWindowTitle('RK 实时视频')
        layout = QVBoxLayout(dialog)
        layout.setContentsMargins(0, 0, 0, 0)
        dialog.canvas = Canvas()
        dialog.canvas.image = self.canvas.image
        layout.addWidget(dialog.canvas)
        close = self.tool('退出全屏', QStyle.StandardPixmap.SP_TitleBarNormalButton, dialog.close)
        layout.addWidget(close)
        dialog.finished.connect(lambda _: setattr(self, 'fullscreen', None))
        self.fullscreen = dialog
        dialog.showFullScreen()
