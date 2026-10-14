"""Native Qt resource pies and shared-scale PCIe payload bars."""
import math
from PySide6.QtCore import Qt, QMargins
from PySide6.QtGui import QColor, QFont, QPainter
from PySide6.QtCharts import QChart, QChartView, QPieSeries
from PySide6.QtWidgets import QWidget, QLabel, QVBoxLayout, QHBoxLayout, QGridLayout, QProgressBar
from telemetry import finite_percent


class ResourcePie(QWidget):
    def __init__(self, title, color, tooltip, parent=None):
        super().__init__(parent)
        self.percent = None
        self.color = QColor(color)
        self.setMinimumWidth(138)
        self.setToolTip(tooltip)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(3)
        label = QLabel(title)
        label.setObjectName('sectionTitle')
        label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        layout.addWidget(label)
        self.series = QPieSeries()
        self.series.setHoleSize(.76)
        self.series.setPieSize(.95)
        self.chart = QChart()
        self.chart.addSeries(self.series)
        self.chart.legend().hide()
        self.chart.setBackgroundVisible(False)
        self.chart.setMargins(QMargins(0, 0, 0, 0))
        self.chart.layout().setContentsMargins(0, 0, 0, 0)
        self.chart.setAnimationOptions(QChart.AnimationOption.NoAnimation)
        self.view = QChartView(self.chart)
        self.view.setRenderHint(QPainter.RenderHint.Antialiasing)
        self.view.setFixedHeight(92)
        self.view.setStyleSheet('background: transparent; border: none;')
        self.value = QLabel('—', self.view)
        self.value.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.value.setStyleSheet(f'font-family: "Segoe UI"; font-size: 25px; font-weight: 600; background: transparent; color: {color};')
        self.value.setAttribute(Qt.WidgetAttribute.WA_TransparentForMouseEvents)
        self.view.resizeEvent = self.resize_chart
        layout.addWidget(self.view)
        self.detail = QLabel('等待采样')
        self.detail.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.detail.setObjectName('muted')
        self.detail.setWordWrap(True)
        self.detail.setMinimumHeight(28)
        layout.addWidget(self.detail)
        self.set_value(None)

    def resize_chart(self, event):
        QChartView.resizeEvent(self.view, event)
        self.value.setGeometry(self.view.rect())

    def set_value(self, value, detail='等待采样'):
        self.percent = finite_percent(value)
        self.series.clear()
        used = self.series.append('已用', self.percent if self.percent is not None else 0)
        free = self.series.append('空闲', 100-(self.percent or 0))
        used.setColor(self.color)
        used.setBorderColor(self.color)
        free.setColor(QColor('#273548'))
        free.setBorderColor(QColor('#273548'))
        self.value.setText('—' if self.percent is None else f'{self.percent:.0f}%')
        self.detail.setText(detail)
        self.value.setGeometry(self.view.rect())


class RateBars(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.values = [None]*4
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(10)
        heading = QVBoxLayout()
        title = QLabel('PCIe 接收码率')
        title.setObjectName('sectionTitle')
        heading.addWidget(title)
        self.total = QLabel('— Mbps')
        self.total.setObjectName('rateTotal')
        heading.addWidget(self.total)
        layout.addLayout(heading)
        self.setToolTip('累计接收JPEG字节数的时间差分；不含PCIe TLP、链路编码和填充开销。三个通道分别按约1秒采样，合计为相近窗口之和。')
        grid = QGridLayout()
        grid.setHorizontalSpacing(12)
        grid.setVerticalSpacing(10)
        grid.setColumnStretch(1, 1)
        self.bars, self.labels = [], []
        for i, (name, color) in enumerate((('通道 A', '#348dba'), ('通道 B', '#15998c'),
                                           ('通道 C', '#cc963c'), ('合计', '#486074'))):
            grid.addWidget(QLabel(name), i, 0)
            bar = QProgressBar()
            bar.setRange(0, 1000)
            bar.setTextVisible(False)
            bar.setFixedHeight(13)
            bar.setStyleSheet(f'QProgressBar {{ border: none; background: #0f172a; border-radius: 2px; }} '
                             f'QProgressBar::chunk {{ background: {color}; border-radius: 2px; }}')
            grid.addWidget(bar, i, 1)
            value = QLabel('—')
            value.setMinimumWidth(76)
            value.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
            grid.addWidget(value, i, 2)
            self.bars.append(bar)
            self.labels.append(value)
        layout.addLayout(grid)
        footer = QVBoxLayout()
        self.description = QLabel('JPEG 有效载荷 · 等待采样')
        self.description.setObjectName('muted')
        footer.addWidget(self.description)
        self.scale_label = QLabel('共用刻度 0–100 Mbps')
        self.scale_label.setObjectName('muted')
        footer.addWidget(self.scale_label)
        layout.addLayout(footer)

    def set_rates(self, values, total):
        self.values = list(values)+[total]
        maximum = max((v for v in self.values if v is not None), default=0)
        scale = max(100, math.ceil(maximum/50)*50)
        for bar, label, value in zip(self.bars, self.labels, self.values):
            bar.setValue(round((value or 0)/scale*1000))
            label.setText('—' if value is None else f'{value:.1f} Mbps')
        self.total.setText('— Mbps' if total is None else f'{total:.1f} Mbps')
        self.description.setText('JPEG 有效载荷 · 约 1 秒采样' if total is not None else 'JPEG 有效载荷 · 等待采样')
        self.scale_label.setText(f'共用刻度 0–{scale} Mbps')
