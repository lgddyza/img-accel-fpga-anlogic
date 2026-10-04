# IMX415 DSI + PCIe JPEG 1080P/60 工程

这是从 `IMX415_DSI_PCIE_GRAY_1080P` 独立整理出的 JPEG 版本。原工程未被删除或覆盖。

## 正确入口

- TD 工程：`fpga_prj_jpeg.al`
- 顶层：`system_top`
- FPGA：PH1A90SEG324-2
- 已验证位流：`verified_output/fpga_prj_jpeg.bit`
- RK 部署包：`deploy/jpeg_rk_bundle.zip`

不要把 `archive_pre_jpeg` 中的文件作为当前工程入口。该目录只用于保留 JPEG 接入前的项目清单。

## 当前数据通路

1. IMX415 输出 1920x1080 RAW10，FPGA 完成 ISP 和 GREY8 转换。
2. 预处理模式 3 依次启用 Gaussian 和上一帧直方图均衡。
3. FPGA 将一帧按 8 行交织分为 A/B/C 三个 1920x360 灰度 JPEG。
4. JPEG A/B/C 分别通过 PCIe C2H1/C2H2/C2H3 传到 RK；C2H0 保留原始 GREY8 调试流。
5. RK 解码三路 JPEG，重新交织为 1920x1080，并经过时域去闪后送 HDMI。

当前 JPEG 参数为 Baseline grayscale、Q85。位流上电或 PCIe 端点复位后默认 30 FPS，RK 必须在停止接收时执行：

```bash
python3 /root/jpeg_rk/jpeg_control.py --rate 60
```

## 手动综合

1. 关闭仍打开原目录工程的 TD 窗口。
2. 打开本目录的 `fpga_prj_jpeg.al`，确认工程路径显示为本目录。
3. 顶层保持 `system_top`，器件保持 PH1A90SEG324-2。
4. 依次执行综合、布局布线、bit 生成。
5. 检查 setup/hold 均无违例，再烧录新生成的 bit。

本目录没有复制旧的 `fpga_prj_jpeg_Runs` 活动缓存，首次综合会创建新的 Run，避免引用原目录的绝对路径。上一次板上验证结果单独保存在 `verified_output`。

## 上一次验证基线

- 时序：SWNS +0.173 ns，HWNS +0.020 ns，STNS/HTNS 均为 0。
- FPGA JPEG：三路约 60 FPS，故障计数 0。
- RK HDMI：约 59.9 FPS，三路未配对帧为 0，去闪启用。
- 原始 GREY8：2,073,600 B/帧，60 FPS 时 995.328 Mbit/s。
- 当前场景 Q85 JPEG：平均 253,512.5 B/组，约 121.7 Mbit/s，压缩比约 8.18:1。

JPEG 大小随路面纹理、噪声、照明和运动变化。最终压缩传输时不要打开 C2H0 原始流，否则 PCIe 上会同时传输原始与压缩数据。

## 目录说明

- `uisrc`：当前 FPGA RTL、约束和厂商 IP。
- `third_party/mjpegZero`：JPEG 编码核及上游说明。
- `al_ip`：PCIe 和时钟相关 IP。
- `sim`：预处理、JPEG 桥接、三分片和连续帧仿真。
- `deploy`：RK V4L2 驱动、JPEG 接收/解码/显示、控制与测量程序。
- `tools`：工程检查、仿真、打包和图像分析工具。
- `verified_output`：已经综合并上板验证的 bit、时序和 QOR，不作为新综合缓存。
- `archive_pre_jpeg`：JPEG 接入前的项目清单，仅用于追溯。
- `captures`：历史抓帧和视觉分析证据。

详细板测见 `BOARD_TEST_JPEG_60_20261004.md`；整个开发状态和寄存器说明见 `PROJECT_HANDOFF.md`。
