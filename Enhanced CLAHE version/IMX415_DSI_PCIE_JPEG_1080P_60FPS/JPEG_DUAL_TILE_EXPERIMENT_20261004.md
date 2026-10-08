# JPEG 双路分带实验记录（2026-10-04）

> 历史记录，双路 150 MHz 在完整高纹理活动行测试中溢出，未作为现行工程交付。当前工程和验收步骤见 `JPEG_TRIPLE_TILE_INTEGRATION_20261004.md`。下文的接线、资源和上板步骤只反映当时的试验设想，不可照此烧录或加载驱动。

## 目标与当前状态

现有 IMX415 灰度、Gaussian、直方图均衡、DSI 显示和 GREY8→PCIe C2H0→RK→HDMI 约 60 FPS 的预览路径保留。新增 FPGA JPEG 采集支路，向 RK 输出约 30 组/秒的压缩静态帧，供道路裂缝保存与分析。**代码和小尺寸 RTL 联合仿真已完成；整个工程的综合、布局布线、实际资源和 RK 上板采集尚待手动验证。**

单个 `mjpegZero Full` 在 150 MHz 下只能处理约一张 1080p 图像的 27.6 ms 工作量；直接从 60 FPS 摄像头隔帧选取时，被选中帧仍在 16.7 ms 内进入，片上 FIFO 无法承担该速率差。因此把每张被选中帧按 8 行交替分成 JPEG A/B 两张图：A 为 1920×544，B 为 1920×536。两个核各以 150 MHz 编码，C2H1 和 C2H2 独立传输；RK 解码后按 A0–7、B0–7、A8–15……交织回 1920×1080。两张是**合法但独立的 JPEG**，不是一张直接可打开的 1080p JPEG。若交付要求单个 JPEG 文件，可在 RK 拼接后再编码或封装为专门的双图格式；本工程保存双 JPEG 和拼接 PGM。

预处理取样点是 `gray_preprocess4` 输出，因此 JPEG 图像含已选择的灰度、Gaussian 和直方图均衡效果。C2H0 和 DSI 不经过 JPEG 核。`jpeg_dual_tile_branch.v` 负责整帧选择、8 行分带、跨时钟 FIFO、两个 JPEG 核、故障锁存和两个字节打包器；不完整的包不发 TLAST，RK DMA 超时后由 B 通道触发 JPEG 支路复位。JPEG 质量默认 85，可在停采时从 RK 设置 1–100。

## 工程与 RK 文件

- TD 工程：`fpga_prj.al`，原工程清单备份 `fpga_prj.pre_jpeg.al`。新增源码位于 `uisrc/01_rtl/jpeg_*.v`、`gray4_to_yuyv4.v` 及 `third_party/mjpegZero/rtl/`。`uisrc/04_pin/timing.sdc` 给 150 MHz JPEG 时钟单独命名。
- RK 内核：`deploy/v4l2_drv/Makefile` 构建原灰度设备和两个 JPEG 设备。A/B 的 V4L2 卡名分别是 `Milianke JPEG Tile A/B`；输出 MJPEG，单缓冲区上限 4 MiB，SGDMA 采用 EOP 结束变长传输。须使用包含 C2H1、C2H2 和 `sgdma_engine_set_eop_flush` 的 SGDMA 驱动。
- RK 用户态：`deploy/jpeg_control.py` 检查双路 ABI 和设置质量；`deploy/capture_jpeg.sh` 调用 `capture_jpeg_tiles.py` 同时收两路、解码、交织并保存 `frame_N.a.jpg`、`frame_N.b.jpg`、`frame_N.pgm`。现有 HDMI 程序继续显示原 GREY8 60 FPS。拼接 PGM 可用于后续静态裂缝算法和 JPEG 损失对照。

## 手动综合与上板顺序

1. 在 TD 打开 `fpga_prj.al`，先运行源码检查，再运行完整综合和布局布线。确认无未定义模块、多驱动、非法约束和时序负裕量；重点查看 `jpeg_enc_clk` 150 MHz、C2H 三通道、ERAM 总数。保存资源报告和最差路径。若 ERAM 超过 272 或 JPEG 时钟负裕量，**不要把新位流当作通过**。先下调 JPEG 输入/输出 FIFO 深度或调整布局；不能仅凭两核单独面积之和断言整机可用。
2. 烧录新位流后先复验 DSI 与原 HDMI 60 FPS 灰度显示。读取 BAR `0xB0`，应为 `0x3247504a`（JPG2）；`0xD4/0xD8` 应为 544/536。若仍是旧 ABI，RK JPEG 驱动会拒绝加载。
3. 在 RK 工程的 `deploy/v4l2_drv` 中，以板端内核的构建目录和 SGDMA `Module.symvers` 编译。示例：`make SGDMA_DIR=/path/to/sgdma_drv KDIR=/path/to/kernel/build`。确保底层 `anlogic_pci.ko` 已加载，再加载 `milianke_gray_v4l2.ko`（若原路径还需显示）、`milianke_jpeg_a.ko`、`milianke_jpeg_b.ko`。通过 `v4l2-ctl --list-devices` 确认三台设备及 A/B 尺寸。
4. 在 JPEG 采集关闭时运行 `python3 deploy/jpeg_control.py 85`，再运行 `bash deploy/capture_jpeg.sh --count 10 --output /tmp/jpeg_tiles`。脚本依赖 Python GI 和 GStreamer 的 `v4l2src`、`appsink`、`appsrc`、`jpegdec`、`videoconvert`。两路须同时开启；只开一路时 FPGA 不选帧。观察 `jpeg_control.py` 的 A/B `sent` 是否同速增长，`faults` 是否保持 0，并独立打开双 JPEG、拼接 PGM 检查条带边界。
5. 连续采集至少 10 分钟，记录 A/B 帧数、无效 JPEG、DMA 超时、BAR 故障数、HDMI 帧率与屏幕稳定性。对同一裂缝图在 Q75/85/95 下比较文件大小、细裂缝召回与误报，再定最终质量；PSNR 不能替代缺陷检测指标。

## 寄存器（User BAR）

| 偏移 | 含义 |
| --- | --- |
| `0xB0` | `0x3247504a`，双路 JPEG ABI 2 |
| `0xB4` | 写 bit0 使能、bit1 脉冲复位；读 bit4 故障、bit3 配置完成、bit2 忙、bit1 两路 DMA ready、bit0 使能 |
| `0xB8` | 质量 1–100，默认 85 |
| `0xBC/0xC0` | A/B 已发送包数 |
| `0xC4/0xC8` | A/B 最近一帧 JPEG 字节数 |
| `0xCC` | JPEG 支路故障次数 |
| `0xD0` | DMA 接收缓冲上限，4,194,304 字节 |
| `0xD4/0xD8` | A/B 高度，544/536 |

## 验证记录和仍需实验的未知

`sim/tb_jpeg_dual_tile_branch.sv` 把 64×24 灰度帧分带，经两个 Full 核、双时钟 FIFO 与 128 bit 包装发送。Xilinx Vivado 2018.3 仿真输出 A=754、B=691 字节，SOI/EOI、TLAST、计数均通过；Pillow 解码尺寸 64×16/64×8，按条带重排后的灰度平均绝对误差 0.465、最大误差 2。此实验验证功能连接，**不能代替 PH1A90 1080p60 时序或 PCIe 实测**。

此前整机约 24,503/64,320 Slice、120/272 ERAM、36/240 DSP；独立 Full 核约 2,256 Slice、61 ERAM、19 DSP。两核简单相加是 29,015 Slice、242 ERAM、74 DSP，ERAM 仅余 30 块，且尚未计入输入/输出 FIFO 和 SGDMA 新通道。最关键的未知是整机 ERAM、150 MHz 时序、PCIe 双路吞吐。最小实验就是先只改变位流为此版本，记录完整 P&R 报告；通过后 Q85 单机连续采集，失败时按 FIFO 故障、DMA 超时和最差路径逐项定位。

双 JPEG 当前按 V4L2 完成时间在 25 ms 内配对；在单侧丢包或复位边界上，这不能保证绝对同源帧。比赛静态样本先检查条带边界并丢弃异常拼接；若要求严格无误配，应在 FPGA 输出协议增加共同的硬件帧号。未来正式商用需复核 `mjpegZero` 的 Apache-2.0 + Commons Clause 许可条件。
