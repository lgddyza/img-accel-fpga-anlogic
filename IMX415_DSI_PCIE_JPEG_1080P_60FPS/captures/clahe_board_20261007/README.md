# CLAHE RK 板测（2026-10-07）

用户确认新 bit 已烧录；COM12 为 RK 控制台，1500000 baud。板测时 PCIe 设备仍在 `lspci` 中，但 BAR/DMA 读数异常；停止旧 HDMI 进程后删除并重新扫描 PCIe 设备，重新加载 `anlogic_pci` 和三路 `milianke_jpeg` 模块，BAR 与视频节点恢复。

## 条件和取样

- FPGA 灰度视频：1920×1080，JPEG QF 85，60 FPS 模式。
- 基线：`preproc_mode.py gauss`，等待 2 秒，抓 5 帧。
- 处理：`preproc_mode.py all`（本次 bit 为 Gaussian＋2×2 CLAHE），等待 3 秒，抓 5 帧。
- 三个 JPEG tile A/B/C 在 RK 解码后按每 8 行交错重组。PNG 为对应 JPEG tile 的解码结果；对比图没有重新均衡或锐化。
- 两组是同机位依次抓取，**不是同一曝光瞬间的帧**。室内照明频闪可能影响亮度比较。

## 数据

| 指标 | Gaussian-only | Gaussian＋CLAHE |
| --- | ---: | ---: |
| 5 帧 JPEG 平均总量 | 125,796 B/帧（122.8 KiB） | 204,056 B/帧（199.3 KiB） |
| 60 FPS 的 JPEG 净载荷估算 | 7.55 MB/s | 12.24 MB/s |
| 两个取回样本的全帧均值 | 65.1、69.5 | 93.2、103.3 |
| 两个取回样本的中心区域标准差 | 18.7、19.9 | 36.0、37.9 |
| 两个取回样本的 255 饱和比例 | 1.28%、1.27% | 1.28%、1.26% |

恢复 HDMI 后，FPGA 三通道在 10.13 秒内各发送 608 帧，约 60.0 FPS，`faults=0`。RK HDMI 日志显示约 57–60 FPS，长期平均约 58.6 FPS，`dropped=0`。显示链保持 `mode=3`、QF 85、60 FPS 模式。

## 文件

- `comparison_gauss_clahe.png`：两组完整画面和灰度直方图。
- `detail_gauss_clahe.png`：固定暗部区域放大。
- `gauss/`、`clahe/`：从板卡取回的原始三路 JPEG tile、重组后 PNG。
- `metrics.json`：逐样本统计数据。
- `analyze_capture.py`：复现重组、统计和绘图。

图像上可见 CLAHE 提高百叶窗和暗部的局部反差；暗部颗粒也更明显。两个样本中未见显著的 2×2 分区接缝。室内场景不能验证道路裂缝的检出率，也不足以证明长时间无闪烁。
