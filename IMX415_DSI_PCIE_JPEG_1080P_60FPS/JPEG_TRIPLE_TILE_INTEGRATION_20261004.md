# JPEG 三路分带工程交接与验收（2026-10-04）

**板测更新：**首版位流的 C 路零帧故障已修复；20:37 位流在 RK 成功接收、解码并重建 1080p，120 秒三路并行测试无故障。最新结论见 `BOARD_VERIFY_JPEG_C_20261004.md`。下文“未完成”描述的是首次交接时状态，以最新板测记录为准。

## 目标与实际交付

保留现有 IMX415→灰度/Gaussian/直方图均衡→DSI 和 GREY8→PCIe C2H0→RK→HDMI 的约 60 FPS 预览。JPEG 支路从同一预处理输出取样，每隔一帧选择一张 1920×1080 图像，以约 30 组/秒为目标传给 RK，供道路裂缝静态分析。预处理模式仍由原寄存器选择；默认模式 3。三路 JPEG 不替代原始预览，原始通道可作无损对照。

HDMI 当前在 RK 端还有逐帧亮度稳定滤镜；JPEG 从 FPGA 预处理输出分支，**没有经过该 RK 滤镜**。因此 JPEG 与屏幕所见亮度可能不同，连续 JPEG 帧也可能保留模式 3 的交替亮度。静态裂缝实验应把预处理模式和采样帧记录下来，必要时对同一场景比较模式 1 与模式 3。

每张选中帧按 8 行交替分给 A、B、C 三个编码器。每路收到 45 组 8 行，独立输出一张合法的 **1920×360 单色 JPEG**。对应 PCIe SGDMA C2H1、C2H2、C2H3。RK 分别接收、解码后按 A0–7、B0–7、C0–7、A8–15……交织，保存 `.a.jpg`、`.b.jpg`、`.c.jpg` 和完整 1920×1080 `.pgm`。三张 JPEG 不能直接作为单个 1080p JPEG 打开；如比赛展示要求单个文件，可在 RK 重排后另行编码为一张 JPEG，但静态裂缝分析宜直接使用拼接后的灰度像素，以避免第二次有损压缩。

三路 `mjpegZero Full` 使用本地 `MONO=1` 修改版，在 200 MHz JPEG 时钟域运行，质量寄存器 Q1–100，默认 Q85。输入每路有 256 个 72 bit 四像素 FIFO 字，输出每路有 128 个 145 bit PCIe 字 FIFO。异常锁存后停止输出完整包，需复位 JPEG 支路；RK 驱动检查 SOI、EOI 和实际 DMA 长度，丢弃不完整帧。FPGA 目前没有共同的硬件帧号，RK 暂按接收时间配对，单路丢帧时存在误配风险，验收时必须检查条带边界。

## 文件入口

| 部分 | 入口 |
| --- | --- |
| TD 工程 | **`fpga_prj_jpeg.al`**；`fpga_prj.al` 是旧 GUI 已加载的源清单，`fpga_prj.pre_jpeg.al` 是原清单备份 |
| 系统接线、BAR、4 路 SGDMA | `uisrc/01_rtl/system_top.v` 的 `pcie_gray_endpoint` |
| 三路选帧、分带与故障控制 | `uisrc/01_rtl/jpeg_triple_tile_branch.v` |
| 格式、跨域、控制、打包、PLL | `uisrc/01_rtl/gray4_to_yuyv4.v`、`jpeg_gray4_axis_cdc.v`、`jpeg_axil_config.v`、`jpeg_byte_packer.v`、`jpeg_clk_pll.v` |
| JPEG 核及许可 | `third_party/mjpegZero/rtl/`、`third_party/mjpegZero/UPSTREAM.md`、`third_party/mjpegZero/LICENSE` |
| RK 驱动与采集 | `deploy/v4l2_drv/Makefile`、`milianke_jpeg_[abc].c`、`milianke_jpeg_v4l2.c`、`deploy/jpeg_control.py`、`deploy/capture_jpeg.sh` |
| 高纹理仿真 | `sim/tb_jpeg_triple_tile_branch.sv`；日志 `E:/FPGA/workspace/jpeg_rtl_evaluation/triple_noise_256_full_xsim.log` |

`uisrc/04_pin/timing.sdc` 已命名 JPEG PLL 时钟。三路试验前，单核、双核和 150 MHz 三核均在高纹理活动行测试中暴露输入 FIFO 溢出；因此当前工程采用三核 200 MHz。不要将 `jpeg_dual_tile_branch.v` 或旧的 `JPEG_DUAL_TILE_EXPERIMENT_20261004.md` 当作现行设计。

## 已完成与未完成的验证

- Xilinx xsim 2018.3 完整 1920×1080、高纹理随机灰度、连续活动行的三路仿真通过：A=466450、B=466615、C=466384 字节，仿真时间约 17.013 ms。三路 JPEG 的 SOI/EOI、TLAST、解码尺寸与行交织在仿真中核对过。三路合计约 1.400 MB，对此极端帧约为 2.074 MB GREY8 的 1.48 倍压缩；真实道路图像的码率需要上板实测。
- `sim/tb_jpeg_triple_continuous.sv` 的小帧连续测试通过：第 0 帧编码、第 1 帧跳过、第 2 帧编码，三路已发包计数均为 2，且无故障。日志在 `E:/FPGA/workspace/jpeg_rtl_evaluation/triple_continuous_xsim.log`。此测试只验证跨帧状态机，不替代全分辨率长时间压力测试。
- 2026-10-04 复查用户的综合失败日志：旧 GUI 工程清单缺少 JPEG 源文件，`fpga_prj_Runs/syn_1/run.log` 在 `read_design` 阶段把 `jpeg_clk_pll`、`jpeg_triple_tile_branch` 判为黑盒。独立的 `fpga_prj_jpeg.al` 含 106 个有效源路径，使用 `tools/td_jpeg_elaborate.tcl` 在安路 TD Release_2026.1_SP2 执行源码读取和 `elaborate -top system_top` 通过；日志 `td_20261004_150158.log` 末尾显示 `finish command "elaborate -top system_top"`，命令行还输出 `JPEG_PROJECT_ELABORATE_PASS`。这一步不包含 optimize_rtl、optimize_gate 或布局布线。
- 该仿真证明选中帧 16.7 ms 活动窗口附近的突发可由当前配置吸收，不能证明 PH1A90 的 200 MHz 时序、PLL 合法性、整机资源或真实 PCIe 吞吐。
- **整机 TD 综合、布局布线、位流和 RK 三路上板采集尚未执行。**板端连接当前不可用；RK 内核模块尚未以板端内核构建目录编译。用户将手动综合，所以这里不把仿真通过写成可烧录结论。

此前整机报告约 24,503/64,320 Slice、120/272 ERAM、36/240 DSP。独立原版 Full 核约 2,256 Slice、61 ERAM、19 DSP；这个数是 YUV422 独立综合，不能直接乘三作为 `MONO=1` 的最终资源数。三核加三组 FIFO、新增 SGDMA 通道很可能使 ERAM 成为第一约束。实际是否装得下只能看此工程的完整资源与布局布线报告。三路 200 MHz 的时序也需要单独通过；输出 FIFO 深度可在 `jpeg_triple_tile_branch.v` 的 `OUTPUT_FIFO_ADDR_WIDTH` 参数调整，但缩小会降低 PCIe 暂停容忍度，必须重新运行压力仿真。

## 手动综合的放行门槛

1. **先关闭当前打开的旧 `fpga_prj.al` 工程，再在 TD 打开 `fpga_prj_jpeg.al`。**它使用独立的工程名和运行目录，含三路分带文件及 `third_party/mjpegZero/rtl` 的 18 个新增源文件。先做源码检查，再完整综合、布局布线、生成位流。旧工程的 GUI 缓存曾把 `fpga_prj.al` 写回旧清单，导致 `jpeg_clk_pll` 和 `jpeg_triple_tile_branch` 被当作黑盒；不要继续在旧工程中点击综合。可运行 `tools/make_jpeg_project.py` 从原清单重新生成独立工程。
2. 检查 PLL 输出 `jpeg_enc_clk` 为 **200 MHz，周期 5 ns**，PLL 参数合法；JPEG 时钟域及跨域约束无未覆盖路径，所有要求收敛的路径 WNS≥0。检查 PCIe IP 的 4 个 C2H 通道、时钟和引脚约束。保存最差路径、Slice/ERAM/DSP、块 RAM 推断及未连接/多驱动报告。任何资源超器件上限或负时序裕量都不能视为通过。
3. 若 ERAM 超限，先据报告定位占用：确认单色模式已裁剪色度缓存；再评估输出 FIFO 从 128 降为 64 字，以及输入 FIFO 从 256 字缩小的可能性。每改一次只变一个参数，重新跑完整高纹理仿真和 TD 布线。若 200 MHz 不收敛，先查编码器关键路径；仅降频会重现活动行 FIFO 溢出，不能直接作为修复。
4. 烧录后先复验 DSI 和原 GREY8 C2H0→HDMI 约 60 FPS 的画面与亮度稳定性，再检查 JPEG BAR。读取 `0xB0` 应为 `0x3347504a`（JPG3），`0xD4/0xD8/0xE4` 均为 360。旧位流会被 RK JPEG 模块拒绝。
5. 在 RK 使用当前板端内核构建目录和同一套 SGDMA `Module.symvers` 编译 `deploy/v4l2_drv`。确保底层 `anlogic_pci.ko` 提供 4 个 C2H、EOP flush 和 `sgdma_engine_set_eop_flush`，随后加载原灰度模块及 JPEG A/B/C 模块。用 `v4l2-ctl --list-devices` 检查三台 JPEG 设备。EOP flush 配置失败时驱动会拒绝开流，因为 JPEG 包长可变。
6. 停止 JPEG 采集时运行 `python3 deploy/jpeg_control.py 85`；随后运行 `sh deploy/capture_jpeg.sh --count 10 --output /tmp/jpeg_tiles`。脚本依赖 Python GI 与 GStreamer 的 `v4l2src`、`appsink`、`appsrc`、`jpegdec`、`videoconvert`。A/B/C 必须同时开流，且三路的 `sent` 计数应同速增长，`faults` 保持 0。检查三张 JPEG 及拼接 PGM 的尺寸、内容和分带边界。
7. 连续采集至少 10 分钟，记录三路帧数、无效 JPEG、DMA 超时、故障数、文件大小、HDMI 帧率和闪烁。对同一批真实道路裂缝图固定机位、曝光、预处理模式和算法，只改 Q75/85/95；按裂缝宽度记录召回率与误报率，同时记录压缩率。用检测指标选 Q，不能只看 PSNR。

## User BAR 寄存器

| 偏移 | 含义 |
| --- | --- |
| `0xB0` | `0x3347504a`，三路 JPEG ABI 3 |
| `0xB4` | 写 bit0 使能、bit1 脉冲复位；读 bit4 故障、bit3 配置完成、bit2 忙、bit1 三路 DMA ready、bit0 使能 |
| `0xB8` | 质量 1–100，默认 85；停 JPEG 采集后修改 |
| `0xBC/0xC0/0xDC` | A/B/C 已发包数 |
| `0xC4/0xC8/0xE0` | A/B/C 最近一帧 JPEG 字节数 |
| `0xCC` | JPEG 支路故障次数 |
| `0xD0` | 每路 DMA 接收缓冲上限，4,194,304 字节 |
| `0xD4/0xD8/0xE4` | A/B/C 高度，均为 360 |
| `0xE8` | 下一版位流的 A/B/C 诊断状态：bit 0–2 输入桥故障、3–5 打包故障、6–8 配置就绪、9–11 输入帧起点已接收、12–14 JPEG 字节已产生、15–17 EOI 已产生。首版烧录位流没有此寄存器。 |
| `0xEC` | C 路修复候选版的首次输入故障细节：bit0–3 C 原因、bit4–13 C 行数、bit14–23 C 行内位置、bit24–27 B 原因、bit28–31 A 原因；原因 bit0=意外 SOF、bit1=行结束错误、bit2=超出行数、bit3=FIFO 满。详见 `JPEG_C_REPAIR_DIAGNOSTIC_20261004.md`。 |

## 后续系统边界

目前 JPEG 支路服务于静态裂缝样本的有损存储与传输。道路裂缝的形态学顶帽、边缘检测、去雾和多尺度滤波不应同时盲目叠加到 60 FPS 主通路：先用拼接 PGM 和原始 GREY8 离线比较召回与误报，再挑单个有效算法决定放到 FPGA 流水线或 RK。严格三路同源配对需要在 FPGA/RK 协议增加共同硬件帧号；现版时间戳配对只适合先期演示与样本采集。第三方核采用 Apache-2.0 加 Commons Clause，未来商业化需要复核许可。
