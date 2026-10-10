# FPGA CLAHE 候选（2026-10-07）

## 目标和接口

活动入口 `fpga_prj_jpeg.al` 的 `gray_preprocess4` 已将模式 2/3 的全局 HE 换成 `gray_clahe4`。两个模块均在 TD 已登记的 `uisrc/01_rtl/gray_preprocess4.v` 中，避免 TD 窗口覆盖独立文件登记时产生黑盒。模式 0 为原灰度，模式 1 为 Gaussian，模式 2 为 CLAHE，模式 3 为 Gaussian+CLAHE。DSI 仍从原有支路取流；CLAHE 作用于送往 JPEG 的预处理支路。输入和输出均为每拍四个灰度像素，1920×1080、60 FPS 的原有帧格式不变。

旧 `gray_hist4.v` 暂留工程供回退；当前 `gray_preprocess4` 不实例化它。独立 CLAHE 文件的备份位于 `tools/gray_clahe4_standalone_source.v.txt`，不参与综合。

## 算法

- 图像分为 2×2 个 960×540 像素区域，每块 256 个灰度 bin；每拍四个像素分别写入四个直方图 bank。
- 每块限幅阈值为该块平均 bin 计数的 2 倍，即当前分辨率下 4050；超过阈值的计数均匀回填到全部 256 个 bin。
- 每块用回填后的 CDF 生成映射 LUT；相邻四块在像素处做双线性插值，边缘延伸至最邻近块中心，避免硬块边界。
- 每块 LUT 对上一帧已发布 LUT 做 1/4 IIR。第一张完整图像生成的 LUT 不平滑；输入帧 N 的直方图用于后续帧 N+1。
- 完整帧才能触发更新。若下一帧在 LUT 构建结束前开始，该帧整帧旁路 CLAHE，错误计数增加，不在同一帧中混用映射。正常 1080p 帧间隔下已在仿真中完成 LUT 构建。
- 1080p 插值权重以定点常数乘法逼近精确比例，误差低于 0.3 个权重单位（满值 256）。四像素计算分级寄存，视频流不停顿，CLAHE 相比旧 HE 增加约两拍流水延迟。

2×2 是受当前片上 RAM 余量约束的第一版局部 CLAHE。它能平滑处理画面不同区域，但局部尺度较粗；若布线后余量允许，再评估 4×3 或更密的网格。密网格还会增加直方图、映射和多端口读取成本，不能只按 LUT 位数估算。

## 验证状态

- `tools/check_sources.py`：TD 清单和 Verilog 静态检查通过，并确认 CLAHE 定义在 TD 已登记的预处理源文件内。
- `sim/tb_gray_clahe4.sv`：小帧四像素逐点参考模型检查限幅、超额回填、空间插值、帧标记和第二帧 LUT IIR。
- `sim/tb_gray_clahe4_1080p.sv`：518,400 个连续四像素输入拍、完整帧统计及下一帧映射启用。
- `sim/tb_gray_preprocess4.v` 与 `_1080p.v`：灰度、Gaussian、CLAHE 串接与模式旁路。

TD 2026.1 SP2 的完整顶层读取展开、RTL 优化及门级综合已在独立目录 `fpga_prj_jpeg_Runs/clahe_synth_check/` 通过。`fpga_prj_jpeg_gate.area` 为 39,778/64,320 slices、240/272 ERAM、110/240 DSP；`fpga_prj_jpeg_gate.ts` 的门级 setup WNS 为 -0.905 ns。最差门级路径位于 200 MHz `jpeg_enc_clk` 域，从 JPEG 第三路输入 FIFO 的读地址寄存器到编码器输入缓存的写位置寄存器；门级 WNS 不是布局布线后的签核结果。旧版布线报告为 40,382/64,320 slices、253 RAM、93 DSP，最终 setup WNS +0.173 ns、hold WNS +0.020 ns。用户仍需在活动 TD 工程中完成布局布线，确认最终 setup/hold 无违例，再生成和烧录 bit。`verified_output` 中的旧 bit 不含 CLAHE。

## 最小上板对照

2026-10-08 的 RK 检测对照见 `../road_damage_yolov8n/runs/rk_preproc_qf_sweep_20261008/REPORT.md`。当前板上 `BAR0+0xAC` 读数为 0，因此不能把现网模式 2/3 当成 CLAHE 实测。候选 RTL 新增 `0xAC=0x434C4831`（`CLH1`）能力标签，以及 `0x100[1:0]` 的帧首已应用模式回读；`deploy/preproc_mode.py` 可用 `clahe --wait-applied` 验证。更新后的预处理小帧仿真和源文件静态检查已通过，但新候选仍需人工完整综合、布局布线、时序签核和上板。

在同一静态路面、相机曝光、室内灯光、QF 和 RK 显示配置下，只切换预处理模式 1 与 3：分别连续记录至少 60 秒的三路 JPEG 接收/重建 FPS、HDMI 实际更新 FPS、FPGA 错误计数、每帧均值/分位数和同位置裂缝细节截图。成功信号是三路仍约 60 FPS、fault=0，局部暗处裂缝可辨性提升，且帧间明暗跳动不显著增加。若 CLAHE 模式产生闪动，优先比较相同输入条件下的帧间亮度统计；RK 显示帧率与 FPGA 处理吞吐分开判断。
