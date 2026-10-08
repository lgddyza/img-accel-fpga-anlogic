# RK JPEG 解码后 HDMI 显示验证（2026-10-04）

## 实现

新增 `deploy/show_jpeg_hdmi.py`：同时读取 FPGA 通过 PCIe 发来的 A/B/C 三路 1920×360 单色 JPEG，按接收时刻配对，分别解码，然后以 8 行为单位交织成 1920×1080 GREY8，送 RK KMS HDMI connector 188。使用 Q85 位流与预处理模式 3。该路径显示的是 JPEG 解码结果；DSI 和原始 GREY8 PCIe 支路均未改动。

首次实现通过 `Gst.Buffer.fill` 复制整帧，送屏仅约 5 FPS。改为 `Gst.Buffer.new_wrapped` 后，软件 JPEG 解码与送屏约 30 FPS。一次三路接收回调的 GI 延迟方法解析竞态导致进程持续异常并在屏幕上露出桌面，现已将方法在主线程预先解析，重启后连续运行。RK MPP 硬解也试过，实测约 4 FPS，因每组三路解码约 88 ms，当前采用软件 `jpegdec`。

## 板上测量

- RK 日志 `/root/jpeg_rk/jpeg_hdmi_live.log` 连续 150 秒：收到 A/B/C=`4505/4506/4505`，重建并送入 HDMI sink 4505 帧，未配对 0；送屏日志约 29.8–30.2 FPS。软件 JPEG 解码三路平均约 20.5 ms/组，拼接 2.2 ms，送帧 2.9 ms。
- 延长到 325.6 秒时，三路各收到 9766 帧，重建 9766 帧，未配对 0，平均 29.99 FPS；FPGA 三路各发 9844 帧、故障 0，日志无 Python 回调异常。
- FPGA 同期 A/B/C 各发 4633 帧，JPEG `faults=0`，三路 bridge/packer fault 均为 0。RK JPEG 帧数与 FPGA 计数的基准起点不同，不能直接相减作为运行时丢帧数。
- JPEG HDMI 运行时，从独立 GREY8 PCIe 支路抓取一张原灰度帧，并用 `SIGUSR1` 从实际 JPEG 送屏路径抓取邻近时刻重建帧。原始均值 149.11，JPEG 重建均值 148.59；黑位占比（<16）4.135%/4.395%，高光占比（>239）17.549%/15.973%。JPEG 带内相邻行平均差 2.86，A/B、B/C、C/A 接缝分别 3.48、3.56、3.41，未见异常突变。
- [近时刻对比图](captures/jpeg_hdmi_compare.png)：整体场景、亮度和可见轮廓接近，JPEG 一侧细纹理略软。四倍缩图的抽样像素 MAE 3.69、PSNR 33.54 dB；两张图片没有共同硬件帧号，场景与曝光可能变化，这不是严格同帧 JPEG 压缩保真度指标。

## 当前状态与限制

RK 当前进程 `/root/jpeg_rk/show_jpeg_hdmi.py --connector 188 --decoder software --capture-dir /root/jpeg_rk/jpeg_hdmi_live` 持续运行；JPEG Q85，模式 3。DRM 状态显示 Xorg 桌面位于 Esmart0 z=0，JPEG kmssink 位于 Cluster0 z=1，均在 HDMI-A-1/video_port0；软件确认 JPEG 帧正送往更高的画面层。首次用户现场观察到桌面时，接收回调正在连续报错；修复后的物理屏幕画面仍需用户目视确认。

此 JPEG 路径的真实新画面速率约 30 FPS，HDMI 输出扫描仍为 1080p@60 Hz。三路 JPEG 按接收时刻配对，尚无共同硬件帧号；单路丢帧时仍可能短时误配。原始 GREY8 的 60 FPS 显示脚本仍保留，可切回对照。
