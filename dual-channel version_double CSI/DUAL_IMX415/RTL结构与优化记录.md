# 双路工程 RTL 结构审查与优化记录

基线为 CLA3；本目录为独立试验副本，基线及其位流未覆盖。工程入口 dual_imx415_gray_demo.al，顶层 dual_imx415_top，器件 PH1A90SEG324-2。

## 结构与资源基线

双路 IMX415 采集和缓存 → 共用图像处理与特征观测 → JPEG 条带编码 → PCIe/DMA → RK。两路前端、各路帧状态和 CLAHE 统计必须保持独立；共享模块需要保留现有仲裁、帧关联和背压协议。

CLA3 实际布线资源：Slice 60921/64320、LUT6 53162/64320、ERAM 248/272、DSP 115/240。层级资源报告中，PCIe 端点层级 174 ERAM（包含其子模块），预处理层级 36 ERAM，ISP 12 ERAM。预处理的黑帽方向开运算占 18 ERAM，CLAHE 占 8 ERAM、34 DSP。层级数字以工具归属为准，不能直接将其理解为模块能安全释放的数量。

最差 JPEG 200 MHz 路径从 DCT 系数索引到乘法器，4.908 ns 路径延迟中布线 2.907 ns；CLA3 setup WNS 报告为 0 ps。优先对该实际路径分段，避免盲目调整双路数据通路或把 FIFO 容量作为空闲资源删除。

## 当前候选 CLA4

在 dct_1d 中提前一周期读取下一个系数，并在乘法前寄存。行起始时与样本快照同步预读第 0 个系数；之后逐周期预读。原输出延迟和每周期输出率保持不变，预计减少索引到 DSP 的组合路径；实际收益以布局布线报告为准。版本 ID 改为 0x434c4134；RK/PC 配套副本增加识别。

验证：随机有效信号、中途复位及 10382 个输出逐周期与 CLA3 DCT 一致；JPEG 三条带、有背压的四帧 1920×48 仿真通过，12 个 JPEG 与 CLA3 逐字节一致；端点寄存器仿真通过。实际 1080p 吞吐及上板功能尚未验证。

项目导入时两份厂商 FIFO 子模块定义存在同名告警；逐模块文本对比显示两份同名模块的定义一致。此检查不能证明所有工具版本的处理均一致，后续宜在独立版本中清理并重新验证。

2026-10-28：TD 正常管理综合流程完成 Read Design、RTL 综合和 gate mapping，实际综合源列表检查及 128 项构建输入哈希通过。gate 阶段估算 Slice 从 CLA3 的 57597 降为 57225，ERAM 246、DSP 115 均不变；综合阶段估计不是最终布局布线占用。gate 估计 setup WNS -2056 ps，布线结果仍待确认。

PCIe IP PLL 源码静态 FIN 为 62.5 MHz，配置逻辑还通过 DRP 根据链路代际写配置。现有约束报告的 125/62.5 MHz 不一致需要结合厂商 IP 的实际工作模式确认，不能仅通过改 SDC 消除告警。DDR 时钟路由、相机 IDDR 复位和未指定 I/O 延时等告警也需分别核实。

## 验收顺序

## CLA4 第一轮最终物理结果（2026-10-28）

TD 正常 managed flow 完成布局布线和 bitgen，最终 setup WNS -0.075 ns、TNS -1.511 ns、38 个违例端点；hold WNS +0.020 ns、无违例。STA coverage 99.76%，不代表其余未约束路径已安全。最终 Slice 60958/64320（94.77%），ERAM 248/272，DSP 115/240。CLA3 的路由结果为 setup 0 ps、hold +8 ps，Slice 60921；因此 CLA4 此轮未达到时序优化验收，资源也没有明显降低。

最差 JPEG 路径为 byte_index 到 packet FIFO 满标志（200 MHz，-75 ps），DDR 时钟域最差为 capture FIFO 到 frame store 写入控制（133.333 MHz，-73 ps，34 个端点），两者网络延迟分别占数据路径约 69%、66%。DCT 原路径不再是全局最差路径，但布线结果不能证明其独立收益。

在 managed route 数据库上单独追加物理优化（四轮、重新修复 hold）无变化，脚本因负 setup 而按设计停止；记录为 build_cla4_polish.log 与 build/cla4_polish/route.ts。这是独立的后处理实验，不替代正常工程构建。

managed bitgen 产物 dual_imx415_gray_demo_Runs/phy_1/dual_imx415_gray_demo.bit 的 SHA-256 为 217021cc6d60f324bfecfccaa410577a5928a85cf2a3b869b214ecafa367d917；其版本 ID 为 CLA4，存在上述时序违例、未进行板测，仅供诊断，不作为通过时序的推荐版本。原 CLA3 基线未覆盖。下一轮需针对 JPEG 打包/FIFO 握手与 DDR 采集写入控制规划流水级，独立验证背压、帧边界、双路吞吐、满 FIFO 和复位，再重新运行完整 managed flow。

核对真实综合源和构建输入 → 完成 Read Design、RTL 综合、门级映射 → 布局布线及约束检查 → 对比 CLA3 时序和资源 → 验证正确版本位流 → 板上测试双路输入、各模式、JPEG/PCIe、HDMI、YOLO 和长期稳定性。任一阶段结果不能替代后续阶段结果。
