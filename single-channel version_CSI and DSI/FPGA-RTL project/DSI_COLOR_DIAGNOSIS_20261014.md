# DSI 灰度画面诊断记录

## 当前结论

**实际板卡持续显示灰度的根因尚未证实，不能把源码检查或仿真通过当作上板成功。**

用户已明确本轮板卡暂时不能连接，只能检查工程。本轮未修改生产 RTL、未重新烧录、未更新 Flash。
此前只修改 DSI 输入连接并完成展开检查，没有验证板上 RGB 像素，这不足以确认目标已完成。

已获得的证据：

- 彩色工程确实已由用户完成综合、布局布线和 bit 生成。
- 下载日志确实记录了两次新 bit 的成功 JTAG 下载，不应再解释为用户没有生成或下载新 bit。
- 本轮数值仿真能够正确还原已知红、绿、蓝输入，经过 ISP 和 DSI 缩放后仍保留颜色。
- DDR 读 FIFO 的 128→32 位转换、OSD 非覆盖区、RGB 打包及 DSI RGB888 包的字节核对通过。
- 这些结果尚不能证明实物相机送出了彩色 Bayer、当前 FPGA 仍运行该 bit，或实体 LCD 正确显示颜色。

## 构建与下载证据

| 项目 | 核对结果 |
| --- | --- |
| 工程 | `IMX415_DSI_PCIE_JPEG_EHP2_DSI_COLOR_20261014/fpga_prj_jpeg.al` |
| 顶层 / 器件 | `system_top` / `PH1A90SEG324-2` |
| bit 生成时间 | 2026-10-14 22:35:48 |
| bit 大小 | 4,850,318 字节 |
| SHA256 | `d989bdff55e931fadc4c4e8499f4806885f692eea349a31b59ded64ae68f48c4` |
| bit 路径 | `fpga_prj_jpeg_Runs/phy_1/fpga_prj_jpeg.bit` |
| 同内容文件 | `best_result/fpga_prj_jpeg.bit`、`phy_1/cw/compiled.bit` |
| 最终时序 | SWNS 0.125 ns，HWNS 0.020 ns |
| 下载日志 | `log/bw_2026-10-14_22-37-00.log` |
| 下载命令 | `download -bit fpga_prj_jpeg_Runs\best_result\fpga_prj_jpeg.bit -mode jtag -spd 7 -cable 0` |
| 下载结果 | 两次 `Downloading succeeded!` |

**需要核验的启动问题：**上述命令是 JTAG 下载。它本身不能证明启动 Flash 被更新；
如果 Flash 中仍是旧灰度版，断电后再启动会加载旧版。这是确定的启动机制，但当前没有
Flash 内容或现场断电时点证据，所以不能直接认定它就是本次故障原因。
现有 EHP2 寄存器标识也不能区分彩色版与灰度版。

## 活动数据通路

```text
IMX415 RAW10 → 解包 / 裁剪 → BLC → Bayer 去马赛克
→ 固定增益 AWB → 边界裁剪 → Gamma → Contrast → Brightness
→ RGB 32 bit/pixel
    ├─ DSI: RGB 缩放 → DDR → OSD → RGB888 打包 → DSI → LCD
    └─ PCIe: 灰度 / 高斯 / Sobel / 黑帽 / 可选 CLAHE → JPEG → RK
```

源码关键位置：

- `uisrc/01_rtl/system_top.v` 的 DSI 缩放器输入直接连接 `S_ISP_O_tdata`。
- `uisrc/03_ip/ui_isp/ui_isp_top.v` 输出 `Color_O_tdata_128`，三个颜色通道独立。
- 旧 `dsi_gray_pack4`、灰度三窗 `ui_video_osd` 的定义仍存在，但没有被活动 DSI 通路实例化。
- `ui_Saturation_adj.v` 的 `GRAYSCALE_ENABLE` 不在当前 ISP 实例链中。
- DSI 数据类型是 `0x3e`，即 RGB888。
- LCD 初始化表与原厂 CSI→DSI 示例的 SHA256 完全一致：
  `490a24da72c4f171150342c15120474ae051582ee43760dc7847057db0c9ec57`。

## 数值实验

运行入口：`tools/run_dsi_color_diagnosis.ps1`。
输出日志：`build/dsi_color_diagnosis/`。

### 实验一：裁剪后 RAW → ISP → DSI 缩放

采用 RGGB 已知色块，检查三个位置：去马赛克输出、ISP 最终输出、DSI 缩放输出。

| 输入 R/G/B | 去马赛克内部像素 | ISP 内部像素 | DSI 缩放内部像素 |
| --- | --- | --- | --- |
| 200 / 30 / 30 | 200 / 30 / 30 | 242 / 98 / 98 | 242 / 98 / 98 |
| 30 / 200 / 30 | 30 / 200 / 30 | 98 / 242 / 98 | 98 / 242 / 98 |
| 30 / 30 / 200 | 30 / 30 / 200 | 98 / 98 / 242 | 98 / 98 / 242 |
| 100 / 100 / 100 | 100 / 100 / 100 | 174 / 174 / 174 | 174 / 174 / 174 |

三个彩色色块的缩放输出各检查 7,168 个像素，7,154 个非灰度，未知值为零；
灰度对照的非灰度像素为零。少量黑边 / 裁剪像素不应算作丢色。

### 实验二：RAW10 字节流 → 解包 / 裁剪 → ISP → DSI 缩放

RAW10 按四像素五字节打包，模拟解包后的 4/5 有效节奏。公开 IMX415 驱动使用
`MEDIA_BUS_FMT_SGBRG10_1X10`；本实验使用传感器 GBRG 输入，在连续第二帧的裁剪后得到 RGGB。
每帧输入 20 行，用第二帧排除原有行规整器首次学习行周期的影响。

三个色块在上述三个位置的内部像素与实验一一致。缩放输出每种检查 6,144 个像素，
6,132 个非灰度，未知值为零；灰度对照没有非灰度像素。

调查过程曾使用 RGGB 作为裁剪前的传感器输入，出现颜色错位。更正传感器 Bayer 假设后
颜色正确，故该现象不能作为修改生产 RTL 的依据。真实模块的原始 Bayer 相位仍需现场确认。

参考驱动：
<https://github.com/rockchip-linux/kernel/blob/develop-5.10/drivers/media/i2c/imx415.c>

### 实验三：DDR 读 FIFO → OSD → RGB 打包 → DSI 包

使用工程原有读 FIFO、OSD、RGB 打包器及 DSI 包模块，将 1,024 个不同 RGB 像素送入：

- 1,024 个读 FIFO 像素逐一完全一致。
- RGB 打包输出 3,072 字节逐一完全一致。
- DSI 包使用 RGB888，word count 为 3,072，全部 payload 字节一致。

### 验证边界

ISP 的厂商 RAM 使用匹配 NOREG 同步读延迟的行为模型；关闭的动态 AWB 除法器使用未启用桩。
DDR 读 FIFO 和打包器使用项目自带 RTL。本轮没有模拟完整 DDR 控制器 / FDMA 事务、
DPHY 电气层或 LCD，也没有运行完整 1,080 行及长期硬件测试。这些实验只检验给定输入下的
颜色处理与字节保存，不能排除实物输入、启动版本或硬件显示问题。

## 恢复连接后的最小定位步骤

1. 保持板卡上电，确认相机视野有明确红、绿、蓝物体，保留 DSI 画面照片。
2. 使用 DSI 专用 RGB 测试块分别注入 DDR 前与 DDR 后，保留原相机 / PCIe / JPEG 分支。
   DDR 后测试块若仍灰度，定位打包 / DPHY / 面板；只有 DDR 前测试块失色，定位 DDR 搬运。
3. 若两处测试块均彩色，读取 RAW Bayer 样本、ISP 输出和 DDR 读出 RGB，逐级比较通道差值。
   配合新的独立 build ID，确认实际运行版本，避免仅用 EHP2 标签判断。

可先利用现有 OSD 背景：它直接产生 `24'h102840`（深蓝色），绕过 ISP 和 DDR。
若背景有蓝色而相机画面灰度，是显示端能呈现颜色的线索；若看不清深蓝色，不能据此下结论，
应使用高饱和度测试块。最终以实际 RGB 数值和现场画面确认丢色位置。

本轮到此完成工程侧核查。故障继续保持“板级根因未证实”，不标记为已修复。
