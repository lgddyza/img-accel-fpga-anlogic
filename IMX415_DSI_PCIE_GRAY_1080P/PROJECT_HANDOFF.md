# IMX415 + 安路 FPGA + RK3576 双屏项目预读与交接

> 更新日期：2026-10-02。本文面向下一轮 RTL、RK 软件开发和上板调试。状态以当前工作区源码、已有仿真/板测记录和用户现场反馈为准；**源码、生成的 bit 文件、实际烧录的 bit 文件不是同一个概念**，每次上板都要重新核对版本。

> **2026-10-02 新候选版本：** PCIe 支路源码已接入 4 像素/时钟的灰度化、高斯滤波、上一帧直方图均衡三级流水线；DSI 支路及 ABI 5 GREY8 输出协议保持原状。四个仿真覆盖模块功能和完整 1080p 帧；TD 独立布线报告为 slice 23,650/64,320、ERAM 117/272、DSP 36/240，setup WNS +0.692 ns、hold WNS +0.020 ns。独立生成的候选位流为 `tools/preproc_candidate.bit`，SHA-256 为 `325D3E58C8FF9A8A54D77B6407B03802A2EECF0F13640819B34CE4915A3C6444`。`fpga_prj_Runs/best_result/fpga_prj.bit` 仍是之前的板测版本，以下段落对“当前源码”或“板上版本”的旧叙述应按本注释区分。候选版本尚未上板验证，也未实现压缩/NPU。

> **上板更新：** 用户已烧录首个预处理候选 bit。RK 重绑 PCIe 后，模式 0/1 有正常图像，HDMI 模式 1 约 60 FPS，用户确认屏幕可见；模式 2/3 的完整 DMA 帧全黑。当前板上留在模式 1。源码已将直方图 ERAM 的同拍读/清零分离，完整 1080p 四级灰度仿真通过。修复位流 `tools/preproc_histfix_candidate.bit` 已完成布线和生成，SHA-256 为 `1B3D098174ABD828B4B0E521243B0E314FB1A0A70C772B38E0D9581B34B64507`，setup/hold WNS 为 +0.573/+0.020 ns；仍需烧录后复测模式 2/3。详情与采样图见 [`BOARD_TEST_PREPROC_20261002.md`](BOARD_TEST_PREPROC_20261002.md)。上段“尚未上板验证”是首个 bit 测试前的旧状态，由本注释取代。

## 1. 目标、当前交付与边界

目标是 IMX415 摄像头经安路 PH1A90SEG324-2 FPGA 采集，在 FPGA 内形成两路同时显示：

| 显示端 | 目标与当前实现 | 已知状态 |
| --- | --- | --- |
| FPGA 直驱 DSI 面板 | 1024×600 面板；完整 16:9 相机画面缩为 1024×576，上下各 12 行黑边；当前为灰度 | 用户已确认完整画面、有黑边，回退灰度后无明显闪屏；最近报告画面有许多“小方格”，原因未定位 |
| FPGA → PCIe → RK3576 → HDMI | 1920×1080、GREY8 灰度，目标 60 帧/秒；RK 负责 HDMI 显示和文字状态层 | 用户反馈灰度画面稳定；实测大多数秒为 60.0 FPS，偶有短帧丢弃 |

双方曾尝试让 DSI 显示原始彩色画面，但出现灰屏、闪屏及紫绿交替。用户明确接受先保持稳定灰度 DSI。因此**不要把“恢复 DSI 彩色”当成当前验收条件**；再次尝试应另开受控实验，不要覆盖已可用基线。

本工程入口是 [`fpga_prj.al`](fpga_prj.al)，顶层 `system_top`，当前主 RTL 在 [`uisrc/01_rtl/system_top.v`](uisrc/01_rtl/system_top.v)。TD 目标器件为 PH1A90SEG324-2。用户自行综合、烧录；改源码后，板上不会自动更新。

## 2. 数据流与几个不能混淆的帧率

```text
IMX415 RAW10 / MIPI CSI
    ↓ 解包、校正、ISP / RGB888，1920×1080，4 像素/时钟
    ├─→ BT.601 灰度复制到 RGB 三通道 → 8:15 最近邻缩图
    │   → DDR 三帧缓冲 → 1024×576 图像 + 12+12 黑边 → DSI 1024×600
    └─→ 独立 BT.601 GREY8 打包 / 异步 FIFO / 整帧检查
        → PCIe SGDMA C2H → RK V4L2 → GStreamer RGBx + 状态文字 → KMS/HDMI 1080p
```

DSI 缩图支路和 PCIe 支路都取自 ISP 输出。PCIe 背压不能反向卡住 DSI，但两个支路共享相机/ISP 前端。当前 DSI 的灰度打包 `dsi_gray_pack4`、缩图 `dsi_color_downscale` 和 PCIe 端点都在 `system_top.v` 中；ISP 主体见 [`uisrc/03_ip/ui_isp/ui_isp_top.v`](uisrc/03_ip/ui_isp/ui_isp_top.v)。DSI DDR 使用每行 256 个 128-bit 写字、576 行；读侧每行 1024 个 32-bit 像素、576 行。

下面三种“60 FPS”各自测量不同的事，调试时须同时记录：

1. DSI 文字层的 `FPS` 计数的是 **DSI 扫描 VSYNC**。50 MHz / (1312 × 635) ≈ **60.015 Hz**，不代表每次都读到不同相机帧。
2. PCIe BAR `0x50` 计数的是经过 FPGA 帧形检查的**完整相机帧**；`0x68` 是丢弃计数，`0x70` 是已交付 DMA 包结束计数，`0x94` 是 PCIe 采集支路的错误计数。
3. HDMI 文字/日志的 FPS 是 RK 视频管线实际送到 HDMI sink 的帧率；HDMI 接口为 1080p@60 只说明扫描时序为 60 Hz，不保证有 60 张新图。

1080p GREY8 一帧 **2,073,600 字节**，按 128-bit DMA 字为 **129,600 beat**；60 FPS 的有效图像负载为 **124,416,000 字节/秒**，还未计 PCIe 协议开销。当前 ABI 为 `0x47520005`，像素格式 BAR `0x4c = 0x59455247`（`GREY`）；宽高 BAR `0x44/0x48 = 1920/1080`，`0x58/0x64 = 2,073,600`，`0x78 = 129,600`，`0x8c` 编码 DSI 1024×600。BAR `0x54` 是写死的名义 60 FPS，不是测量值。

## 3. 到目前为止真正验证过的状态

- 当前双屏灰度版本经用户综合、烧录后，用户反馈 DSI 画面完整且有黑边，回退到明确灰度后 DSI 不再明显闪屏；用户反馈 HDMI 灰度画面稳定。**DSI“小方格”仍是新问题，尚无照片、尺寸和固定/随场景变化的观察记录。**
- 当前源码的完整 1920×1080 RGB 合成帧缩图仿真，逐像素对照独立 8:15 最近邻参考，通过 1024×576 输出、576 个行尾和唯一帧起点检查。灰度打包、DSI 文字层、PCIe 灰度跨时钟打包、短帧中止也有对应仿真。静态工程检查覆盖 TD 源文件清单、局部 Verilog 语法和端口连接，但不能代替 TD 综合、布线或硬件验证。
- 现有 TD 结果的最近一次生成时间为 **2026-10-02 03:01**，见 [`fpga_prj_Runs/best_result/fpga_prj.bit`](fpga_prj_Runs/best_result/fpga_prj.bit)。对应 [`route_flow.status`](fpga_prj_Runs/phy_1/route_flow.status) 报 setup WNS 719 ps、hold WNS 20 ps，TNS 均为 0。不能仅凭文件时间证明这就是板上正在运行的 bit。
- FPGA/RK 测试曾在严格 GREY8 V4L2 模式连续抓到完整 2,073,600 字节帧；RK 端的 HDMI 插口也曾由 DRM 报告为 1920×1080@60。保留的 [`captures/`](captures/) 图片主要是 RK 原始帧或 HDMI sink **输入缓冲**，不是屏幕光学照片、也不是 HDMI 端口回读。
- RK 端在移除旧 `videorate` 30 FPS 限制、启用 KMS `skip-vsync=true` 和小区域原位绘字滤镜后，持续观察中 HDMI sink 大多数秒为 **60.0 FPS**；一次含启动阶段的 5 秒测试为 299 帧。单次观察还见到约每 17 秒一个长度 **1,056,768 字节**的短包被严格驱动拒收，导致个别秒约 58 FPS。这个频率不是已证明恒定的设备特性。

## 4. 已踩过的坑、诊断结论与处理

| 现象 | 经验证的原因或证据 | 当前处理与下次注意 |
| --- | --- | --- |
| 早期 1080p DMA 只有 1066 行 | 老工程相机裁剪窗口 `v_start=19, v_end=1100`，实测包长 2,046,736 字节，少 14 行；仿真重现 | 当前双屏工程按 1080 行检查。旧 `diagnostic_short_1066=1` 仅供老 bit 诊断，当前 ABI 5 驱动应关闭。不要用补黑行冒充完整采集。 |
| FPGA 刚重新烧录后 RK 端超时或端点失效 | RK 上旧 PCIe BAR / DMA 映射仍指向复位前的端点 | 停止旧 viewer，卸载灰度 V4L2 与 SGDMA 模块，重绑 RK `2a210000.pcie`，再装与 ABI 匹配的模块；参考旧部署脚本 [`pcie1_rebind.sh`](../IMX415_PCIE_X1/deploy/pcie1_rebind.sh) 或 [`pcie_smoke_demo/vendor_deploy`](../pcie_smoke_demo/vendor_deploy/)。先恢复链路，再判断图像代码。 |
| HDMI 看起来“灰蒙蒙”，R/G/B 不等 | 灰度 V4L2 驱动给出 `colorimetry=2:0:0:0`；GStreamer 转 RGBx 时曾输出 `(Y,128,128)` | 当前 [`show_gray_hdmi.py`](deploy/show_gray_hdmi.py) 先用 `capssetter replace=true` 清掉错误色彩元数据，再 `videoconvert`。曾对 sink 输入采样确认图像区 R=G=B。调亮度/对比度不能代替格式修正。 |
| HDMI 曾一亮一暗交替 | 连续 120 张原始 GREY8 帧已有双态亮度差，lag-one 相关约 -0.991；画面中拍到的发光显示器是另一台电脑。交替已经存在于 RK 视频转换之前，根源仍未证明 | 固定相位取 30 FPS 曾抑制可见交替，但会牺牲 60 FPS；当前 60 FPS 显示版本不靠该办法。若复发，先用稳定直流照明、移走被拍显示器，只改变光源这一变量重抓原始帧。 |
| 工程师怀疑课程工程的 `mipi_csi_rx.v` | 该文件属于另一套课程 MIPI 接收实现，未被当前 TD 工程实例化；当前活动 `al_ip/mipi_rx` 五个文件与提供的 `415_mipi` 参考逐字节相同 | 不要直接替换未入源清单的文件。要查 MIPI 时先从 `.al` 源清单、实例链、实际综合日志出发。 |
| DSI 只显示左上角、没有完整画幅 | 旧 DDR 读参数相当于从 1920 宽帧缓冲读 1024×600 窗口 | 当前先缩图至 1024×576 并紧凑写 DDR，再 1024 像素行距读取，扫描端加入 12 行上下黑边；全帧仿真已通过。 |
| DSI 彩色尝试后仍灰、后来紫绿闪动 | 曾尝试绕过 ISP 饱和度灰度级、增加 DSI 专用 AWB/饱和度；屏幕状态框是蓝色但相机图仍灰；进一步改动后用户见紫绿交替 | 用户选择回退。当前 DSI 在缩图前显式把每像素变成 `{0,Y,Y,Y}`；AWB/饱和度分支不在活动路径。蓝色状态框只能证明 DSI 物理输出能显示颜色，不能证明相机图像链路有正确色度。 |
| DSI 曾闪屏 | 原扫描时序 50 MHz/(1344×635)≈58.59 Hz，相机约 60 Hz，帧缓冲读写相位会快速漂移；改为 1312×635≈60.015 Hz 后用户反馈稳定 | 这个时序改动是合理原因之一，但没有单独隔离证明它解释了此前所有闪动。不要恢复旧 HTOTAL。 |
| TD 报 `dsi_frame_awb is a black box` | AWB 独立模块文件未进入/被 TD GUI 覆盖的项目源清单 | 曾将模块置于已登记的 `system_top.v` 中解决清单问题，后来整条彩色 AWB 支路已撤回。新增模块时先检查 `.al` manifest 和综合日志，不要只看磁盘上文件是否存在。 |
| HDMI 只有 20–30 FPS | 旧 viewer 明确加了 30 FPS `videorate`；去掉后 RGBx 路径又被 KMS 等待垂直同步和大文字层拖慢 | 当前 `skip-vsync=true`、小面积 `rkfastosd` 使 RK sink 大多达到 60 FPS。插件缺失会退回标准 `textoverlay`，需看启动日志确认实际分支。 |
| 偶发 1080p 短帧 | 严格驱动拒绝 1,056,768 字节短包；同一 18 秒区间 FPGA 采集错误 +2、丢弃 +1 | 不能靠 RK 显示优化补回不存在的相机帧。优先同时采 BAR 计数、FIFO/帧形检查和 DMA 完成信息；未定位到单一 RTL 根因。 |
| DSI “很多小方格” | 当前缩图为无预滤波的 8:15 最近邻抽样，细纹理可能产生摩尔纹；但规则块状损坏也可能来自更后面的 DDR/读出，**尚不能定因** | 先拍近照，并让相机看平滑墙面和细纹理各一次；记录方格是否固定在屏幕坐标、是否跟着场景移动，比较同时刻 HDMI 图像及 DSI 状态文字是否清晰。若只随细纹理出现，优先验证缩图前低通/区域平均；若固定或跳动，查缩图输出计数、DDR FIFO/读有效。 |

> 原始 `demo` 的大块多窗 OSD/高斯/直方图均衡逻辑占用较多 BRAM。双屏 + PCIe 版为了资源与布线，未实例化该大 OSD。`gray_gauss_equalize.v`、`gray_hist_equalize.v` 等文件仍可供算法参考，**存在源码文件不等于当前数据流已经使用**。

## 5. 下一轮开发与启动顺序

1. **先冻结可用基线。** 记录当前 `.bit` 的完整路径、生成时间和哈希，以及板上实际烧录的文件；备份当前 [`system_top.v`](uisrc/01_rtl/system_top.v)、[`ui_isp_top.v`](uisrc/03_ip/ui_isp/ui_isp_top.v) 和 RK viewer。确认本次只修改一个支路或一个可验证假设。
2. **读源清单再改 RTL。** 打开 [`fpga_prj.al`](fpga_prj.al)，确认新文件已注册、顶层仍为 `system_top`，目标器件和约束没变。用可用的 Python 解释器运行 `tools/check_sources.py`，再跑受影响的仿真；当前 Windows 的 `python` 命令可能指向无法启动的 WindowsApps 占位程序，本次用 Codex 自带解释器运行该检查并通过：85 个工程文件存在、14 个本地实例端口检查通过、126 个参考文件未意外改动。TD 综合、时序检查和烧录由用户执行。静态检查通过不能视为综合通过。
3. **烧录后先看本地 DSI。** 检查上/下 12 行黑边、完整画面、灰度、状态文字、闪动和方格；DSI 文字 `FPS` 只证明扫描时钟。拍屏记录视觉现象，勿用 RK 截图冒充 DSI 实际画面。
4. **再恢复 RK PCIe。** 如果重新烧录后 BAR 失效，按上表清旧 viewer/驱动和重绑 PCIe。核对 BAR `0x44/0x48/0x4c/0x58/0x5c/0x78` 为 ABI 5、1080p GREY、完整帧，再加载对应灰度 V4L2 驱动；不要同时加载旧 RGB wrapper。`/dev/video73` 和 HDMI connector ID `188` 是已用过的板上取值，换系统后应重新枚举。
5. **再测原始帧与 HDMI。** 先抓多张 V4L2 GREY8，逐张要求 2,073,600 字节；比较图像内容和相邻帧亮度，再运行 [`deploy/show_gray_hdmi.sh`](deploy/show_gray_hdmi.sh)。记录 BAR `0x50/0x68/0x70/0x94` 的前后差值、RK sink FPS 和 DRM 模式。看到约 60 Hz HDMI 模式时仍要核对实际新帧数。
6. **任何新故障都做单变量实验。** 优先给出“修改的唯一变量、预期成功/失败信号、需要回收的数据”。尤其别同时换 bit、驱动、相机照明和显示脚本，否则很难定位闪动、短帧或方格。

RK viewer 使用 [`deploy/show_gray_hdmi.sh`](deploy/show_gray_hdmi.sh)，优先自动寻找 `Milianke PCIe GREY` 设备；脚本可显式传入设备和 connector。它需要 RK 端 Python GI/GStreamer、灰度驱动和 `kmssink`；[`deploy/build_rk_fast_osd.sh`](deploy/build_rk_fast_osd.sh) 用 RK 本机 C 编译器和 GStreamer 开发包构建小面积文字滤镜。开发机连 RK 的串口为 **COM12、1,500,000 baud**；现有 [`serial_command.ps1`](../pcie_smoke_demo/tools/serial_command.ps1) 可用于命令/读数。曾用过的直连 SSH 地址和 `/dev/video73` 一样属于当时环境，不应写死成保证可用的接口。

## 6. 工作区工程如何分工

| 位置 | 建议用途 | 注意 |
| --- | --- | --- |
| [`workspace/demo`](../demo/) | 相机 CSI、ISP、DDR、DSI 的原始可运行基线；灰度、高斯、直方图均衡和大 OSD 的参考 | 不是当前双屏 PCIe 的烧录工程，重资源 OSD 未进入当前活动路径 |
| [`workspace/IMX415_PCIE_X1`](../IMX415_PCIE_X1/) | 厂家 PCIe RGB/SGDMA 原型、部署脚本和驱动来源 | 老格式/帧尺寸和 ABI 不等于当前 GREY ABI 5 |
| [`workspace/IMX415_PCIE_GRAY_1080P`](../IMX415_PCIE_GRAY_1080P/) | 独立 1080p GREY over PCIe 阶段，含 1066 行裁剪错误的记录与修复思路 | 没有 DSI 输出；其 README 涉及“未烧录”的历史状态，只作为故障回溯 |
| [`workspace/IMX415_DSI_PCIE_GRAY`](../IMX415_DSI_PCIE_GRAY/) | 较早的 DSI 镜像 + PCIe 1024×600 方案 | ABI 4、614,400 字节/帧；不能与当前驱动混用 |
| **[`workspace/IMX415_DSI_PCIE_GRAY_1080P`](./)** | **当前主工程：DSI 1024×576 灰度全帧 + RK HDMI 1080p GREY** | 下一轮改动从这里开始，保留 `README.md` 与本文的历史证据 |
| [`workspace/pcie_smoke_demo`](../pcie_smoke_demo/) | PCIe 枚举、BAR、SGDMA 连通和 RK 串口/部署工具 | 原始 RGB 演示配置不是当前最终视频格式 |

用户最初提到的失败融合尝试 `PCIE_DSI`，在当前 `workspace` 目录清单中没有独立的同名目录；上表两个 `IMX415_DSI_PCIE_GRAY*` 是后续可追溯的集成阶段。不要凭名称相近误开旧 `.al` 或烧旧 `.bit`。

## 7. `E:\FPGA` 资料目录索引与阅读优先级

以下是按**本项目相关性**筛选的目录说明，不是所有压缩包/课件的逐文件解读。建议先看 ① 当前项目 README/本文，② 异构 PCIe 教程与原版工程，③ 板卡硬件资料，之后按故障查专项资料。

| 资料位置 | 有用内容 / 适用时机 |
| --- | --- |
| [`03_course/07_异构方案/AFC03_IMX415_PCIE_X1/米联客2026版异构AFC03教程-PCIE篇.pdf`](../../03_course/07_异构方案/AFC03_IMX415_PCIE_X1/米联客2026版异构AFC03教程-PCIE篇.pdf) | 厂商的 FPGA–RK PCIe 异构方案入门；理解端点、SGDMA、RK 部署时优先看。旁边的 [原始 PCIe 工程](../../03_course/07_异构方案/AFC03_IMX415_PCIE_X1/AFC03_IMX415_PCIE_X1/IMX415_PCIE_X1/) 可对照相机与 PCIe 实现。 |
| [`03_course/07_异构方案/415_mipi/uisrc/03_ip/al_ip/mipi_rx`](../../03_course/07_异构方案/415_mipi/uisrc/03_ip/al_ip/mipi_rx/) | 活动 MIPI RX 实现的参考副本；当前主工程相应五个文件曾比对为相同。调查 MIPI 时先比源清单和实例链。课程原始工程的 `mipi_csi_2/mipi_csi_rx.v` 属另一实现，不能直接认为会影响当前 bit。 |
| [`03_course/07_异构方案/dts/rockchip/rk03/pcie.dtsi`](../../03_course/07_异构方案/dts/rockchip/rk03/pcie.dtsi) 与 [`HDMI.dtsi`](../../03_course/07_异构方案/dts/rockchip/rk03/HDMI.dtsi) | RK3576 PCIe/HDMI 设备树参考；在枚举失败、显示节点不见时查。目录内还含多种 CSI/屏幕外设 dtsi，勿直接整套覆盖当前板上 DTB。 |
| [`03_course/07_异构方案/driver/milianke_mipi.c`](../../03_course/07_异构方案/driver/milianke_mipi.c) | 厂商 RK 侧 MIPI 驱动参考；当前 PCIe GREY V4L2 驱动应以本工程 [`deploy/v4l2_drv`](deploy/v4l2_drv/) 为准。 |
| [`02_hardware/HW_MLK_AFH03_20250402_AFC03_20250402_RK+AL/01_硬件手册`](../../02_hardware/HW_MLK_AFH03_20250402_AFC03_20250402_RK+AL/01_硬件手册/) | AFC03/AFH03 核心板、底板接口、供电与使用说明；硬件连线、JTAG、时钟、摄像头/屏幕问题先查。 |
| [板卡原理图](../../02_hardware/HW_MLK_AFH03_20250402_AFC03_20250402_RK+AL/02_原理图/) 与 [框图及 pinlist](../../02_hardware/HW_MLK_AFH03_20250402_AFC03_20250402_RK+AL/08_框图及pinlist/) | 核对 FPGA–RK PCIe、MIPI、CSI/DSI、HDMI、UART 和连接器引脚。**管脚以实际原理图及当前板卡版本为准**，文件夹里有“仅供参考”的引脚定义表。 |
| [`01_start/00_start_fpga/02_peripheral_demo/06_csi_2_dsi_imx415_7cun`](../../01_start/00_start_fpga/02_peripheral_demo/06_csi_2_dsi_imx415_7cun/) | 厂商 IMX415 → DSI 最小外设演示，可在隔离 DSI/DDR/相机问题时对照。`05_tpg_dsi_7cun` 可用图样源排除相机影响。 |
| [`01_start/00_start_fpga/00_for_starter`](../../01_start/00_start_fpga/00_for_starter/) 与 [`01_board_test`](../../01_start/00_start_fpga/01_board_test/) | TD 软件快速入门和开发板上电测试；换机器或 JTAG 环境时使用。 |
| [`01_start/01_start_linux`](../../01_start/01_start_linux/) 与根目录三个“Linux 系统 / 设备开发 / 驱动开发” `.docx` | RK3576 系统恢复、串口、设备驱动基础。只在需要改系统镜像、内核、设备树或驱动时深入；当前先依赖已验证的板上系统。 |
| [`软件&驱动`](../../软件&驱动/) | JTAG 驱动、TD license 与常用工具；开发机不能识别下载器时查。 |
| [`全国大学生嵌入式芯片与系统设计竞赛'2026FPGA赛道选题指南-安路科技.pdf`](../../全国大学生嵌入式芯片与系统设计竞赛'2026FPGA赛道选题指南-安路科技.pdf) 与 [`安路赛道方向三学习路线与项目计划.md`](../../安路赛道方向三学习路线与项目计划.md) | 比对竞赛方向、演示目标和后续功能规划；技术实施以当前可测工程为基线。 |
| 根目录 `mlk-sdk-3576-v1.1.0.tar.gz`、`uisrc-ubuntu22.04-V2.0.7z` 和硬件 `.rar` | 大型 SDK/源码/硬件资料归档；按需解压，不要在排查单一视频问题时直接覆盖工作区。 |

## 8. 下一轮最值得验证的共同未知

| 假设 | 只改变一个变量的最小实验 | 成功/失败信号与需保存的数据 |
| --- | --- | --- |
| DSI“小方格”是无预滤波最近邻缩图导致的混叠 | 固定相机/曝光，先拍平滑墙面，再拍细密纹理；保持 bit 与 RK 不变 | 方格仅随细纹理/场景移动 → 支持混叠；若在平滑墙面仍固定成块 → 优先查 DDR/像素路径。保存 DSI 近照、同场景 HDMI 帧、方格宽高像素数。 |
| HDMI 偶发短帧来自相机/ISP 边界或 FIFO，而非 RK sink | 不改显示参数，连续记录严格 V4L2 帧长和 BAR `0x50/0x68/0x70/0x94` 差值 | 错误计数与短包同时增长 → 上游采集路径；BAR 稳定而 RK 缺帧 → 再查驱动/调度。保存时间戳、短包长度、四个计数前后值。 |
| 亮度交替由被拍电脑屏幕/光源拍频产生 | 固定所有软件和相机参数，只移出被拍电脑屏幕或换稳定直流光 | 原始连续 GREY8 帧中的偶/奇均值差消失 → 支持场景/照明原因；仍存在 → 查传感器曝光、ISP 帧同步。保存至少 120 帧的统计及照明条件。 |

**交接验收建议：** 每次新 bit 至少保留“源码版本/bit 哈希、TD 时序摘要、DSI 实拍、BAR 寄存器快照、连续原始帧长度统计、HDMI sink FPS 日志”六项。这样下一位开发者才能区分图像算法、时序、PCIe 传输与 RK 显示问题。
