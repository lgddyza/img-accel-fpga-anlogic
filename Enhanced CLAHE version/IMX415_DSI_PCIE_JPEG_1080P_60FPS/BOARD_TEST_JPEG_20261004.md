# RK3576 JPEG 板测记录（2026-10-04）

## 测试对象

- FPGA 已烧录 `fpga_prj_jpeg_Runs/best_result/fpga_prj_jpeg.bit`（生成于 15:37）。本记录后续 RTL 修改均不在该位流内。
- RK 通过 PCIe 枚举 `1edb:abcd`。重新初始化 PCIe 后，SGDMA 识别 1 个 H2C、4 个 C2H。BAR `0xB0=0x3347504a`，A/B/C 高度均为 360，JPEG 质量 85。
- RK JPEG 驱动在板端内核 6.1.99 上编译并加载。A/B/C 对应 `/dev/video74`、`/dev/video75`、`/dev/video76`；灰度 `/dev/video73`。

## 实际结果

| 项目 | 结果 |
| --- | --- |
| GREY8 C2H0→RK→HDMI | 运行中，日志显示 1920×1080 约 58–60 FPS，RK 亮度稳定滤镜启用。屏幕画面需用户目视确认。 |
| JPEG A / C2H1 | 成功。关闭错误自动复位的单组试验输出 57,099 字节，JFIF 单色 1920×360；GStreamer `jpegdec` 解码成功。 |
| JPEG B / C2H2 | 成功。同组输出 57,208 字节，JFIF 单色 1920×360；GStreamer `jpegdec` 解码成功。 |
| JPEG C / C2H3 | 失败。10 秒内零帧，SGDMA C2H3 多次 200 ms 超时；BAR `sent_C=0`、`bytes_C=0`。 |
| FPGA JPEG 状态 | 停止自动复位后 `configured=1`、`busy=1`、`fault=1`、`faults=1`。A/B 各发送 1 帧后支路停在故障态。 |

正常自动复位时，10 秒窗口收到 A/B/C=`39/40/0`。质量降至 Q50 后 C 仍为 0，故障不能仅由 Q85 码流较大解释。RK 曾因 16 MB CMA 无法分配每路 4 MB 连续缓冲而不能开流；驱动已经改用 scatter-gather vb2 缓冲并在板端重编译，当前 A/B 正常接收。关闭复位后的 JPEG 保存在 RK `/root/jpeg_rk/no_reset_capture/unpaired_a.jpg` 和 `unpaired_b.jpg`。采集结束后保留 HDMI 预览运行。

## 已准备的下一版位流

- `jpeg_triple_tile_branch.v` 增加 A/B/C 输入被接受、编码字节、EOI、输入桥故障、输出打包故障等状态，`system_top.v` 暴露为 BAR `0xE8`。当前烧录位流读不到这些新状态。
- `quantizer.v` 把 Q 表读取与乘法分到相邻时钟周期。当前位流的 200 MHz JPEG 时钟最差 WNS 为 **-0.907 ns**，最差路径是 Q 表 ERAM 到 DSP。该修改意在切断已知路径；**未经过新一轮布局布线，不代表时序已收敛，也不能断言它就是 C 故障的原因**。
- `milianke_jpeg_v4l2.c` 新增可写参数 `recover_on_error`。诊断时设置 C 模块该参数为 `0`，保留 FPGA 故障现场；平常默认 `1`。
- 更新后的 RTL 已通过三路连续小帧 xsim（`JPEG_TRIPLE_CONTINUOUS_PASS sent=2/2/2`）和 TD `elaborate -top system_top`；未运行完整综合。

## 下一次最小实验

1. 用户用 **`fpga_prj_jpeg.al`** 手动综合、布局布线。先核对 200 MHz JPEG 时钟 WNS≥0；若仍为负，保存新最差路径，不应把它作为稳定运行位流。然后烧录新位流。
2. RK 重新初始化 PCIe，确认 BAR ABI，再运行一次 Q85 三路采集。C 驱动置 `recover_on_error=0`，首个超时后读 `python3 /root/jpeg_rk/jpeg_control.py` 的 BAR `0xE8` 六组 A/B/C 位。单次采集只观察这项新增诊断量，不同时调整质量或 FIFO 参数。
3. 若 C 的 `input_seen=0`，检查分带、SOF 和输入 CDC；若输入已见而 `jpeg_byte_seen=0`，查编码器配置与就绪；若字节已见但无 EOI，查编码器内部停滞或输入丢行；若 EOI 已见但 `sent_C=0`，查输出打包 FIFO 与 SGDMA C2H3。保留 `fault` 位和 dmesg，再决定单点修复。

当前三路 JPEG 尚未达到验收条件，不能进行三带 1080p 重建或声称压缩传输完成。
