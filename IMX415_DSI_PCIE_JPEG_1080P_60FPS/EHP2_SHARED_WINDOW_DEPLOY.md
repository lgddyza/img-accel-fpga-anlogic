# EHP2: 共享窗口、3x3 黑帽与增强后 CLAHE

## 交付范围

本版对应已确认需求：最终单路视频，RK 经 PCIe 动态选择预处理；灰度、高斯、Sobel 和黑帽并行流水，选中一路后可叠加 CLAHE。黑帽闭运算核为 3x3，gain=1，保留四方向 line5 响应滤波。原灰度、高斯、CLAHE、高斯+CLAHE 模式保留。

当前状态（2026-10-10）：用户已完成布局布线、生成并烧录EHP2位流；RK已读回EHP2/FF，完成八模式抓图、HDMI+YOLO性能测试和连续运行中的动态切换。黑帽K3 gain1及增强后CLAHE均已在板上运行，硬件故障寄存器均为0。RK已恢复模式3、QF90及原HDMI+YOLO启动方式。详见本文末尾板测记录；裂缝召回率和严格60 FPS HDMI尚未验收。GUI 工程为 `fpga_prj_jpeg.al`，顶层 `system_top`；算法模块均定义在已登记的 `uisrc/01_rtl/gray_preprocess4.v`。

## 数据通路

```text
RGB -> 灰度 -> 原 Gaussian 的共享 3x3 窗口
                 |-> 中心灰度 -------------------------------|
                 |-> Gaussian -------------------------------|
                 |-> Sobel 引导增强 --------------------------|-> 帧锁存选择
                 |-> 3x3 max(膨胀) -> 3x3 min(腐蚀)           |       |
                     -> 黑帽响应 -> 四方向 line5 opening      |       v
                     -> gain1 原图暗化增强 --------------------|   CLAHE/直通
                                                                     |
                                                   原单路 JPEG/PCIe 视频
```

共享的是原灰度邻域和黑帽首级膨胀。黑帽第二级腐蚀输入是膨胀图，不能复用原灰度窗口；后续方向滤波也有自己的缓存。CLAHE 只有一套，位于选择器之后。无需为不同增强分支重复配置 CLAHE。

设灰度为 I，C=erode3(dilate3(I))，B=max(C-I,0)。四个方向的长度5开运算响应取最大值为 D，输出为 max(I-D,0)。这里是对暗裂缝的暗化增强，不是直接输出黑帽响应图。Sobel 仍为原 T1、gain0.5 参数。

3x3 会降低宽裂缝的黑帽响应，也可能削弱部分斜向细裂纹；gain1 可能加重残余纹理。资源节省不等于召回率提升，需要新位流同场景检测对比。

## 模式与寄存器

| 编号 | RK 名称 | 输出顺序 |
| --- | --- | --- |
| 0 | gray | 灰度 |
| 1 | gauss | 灰度 -> Gaussian |
| 2 | clahe | 灰度 -> CLAHE |
| 3 | gauss-clahe / all | 灰度 -> Gaussian -> CLAHE |
| 4 | sobel | 灰度 -> Sobel 引导增强 |
| 5 | blackhat | 灰度 -> K3 黑帽 gain1 + line5 |
| 6 | sobel-clahe | 灰度 -> Sobel 引导增强 -> CLAHE |
| 7 | blackhat-clahe | 灰度 -> K3 黑帽 gain1 + line5 -> CLAHE |

- `0xAC`: 算法标识 `0x45485032` (EHP2)。
- `0x104`: 支持模式位图 `0x000000FF`。
- `0xA4`: 请求模式，合法范围0..7，非法写入退回0。
- `0x100`: 输入帧 SOF 锁存后的模式反馈。
- `0xA8 bit0`: 预处理缓存溢出、对齐或帧重叠故障。

模式在输入 SOF 锁存。各分支需要在下一帧开始前排空，不能在行中随意切换输出。模式反馈确认锁存，不代表下游已消费完上一帧。

CLAHE 持续学习选中的输入流，采用前帧 LUT 和已有 IIR 平滑。切换增强分支后，最初输出会受旧分支直方图影响，等待数帧并观察稳定结果后再做视觉比较。未实现自动场景识别或自动选择策略。

## RK 使用

重新烧录后，将本工程 `deploy/preproc_mode.py` 更新到 RK 原脚本位置。在该目录以 root 运行：

```sh
python3 preproc_mode.py status
python3 preproc_mode.py blackhat --wait-applied
python3 preproc_mode.py blackhat-clahe --wait-applied
python3 preproc_mode.py sobel-clahe --wait-applied
python3 preproc_mode.py gauss-clahe --wait-applied
```

脚本兼容 EHP1 和 CLH1，旧位流会拒绝6/7组合，避免错误写入。EHP1 的 blackhat 仍是 K7 gain0.5；只有 EHP2 才是 K3 gain1。

## 验证记录

已通过17帧、8模式的小尺寸回归，检查独立 OpenCV 整数像素参考、独立 CLAHE、边界、valid 空隙、帧中请求变化及故障，日志为 `sim/ehp2_small.log`。完整1080p像素仿真覆盖 Sobel/黑帽各一帧，共1,036,800四像素拍，无丢像素或错误帧行标记。连续输入首像素延迟为 Sobel492拍、黑帽2905拍。证据为 `tools/ehp2_sim/pixels/simulate.log`。

2026-10-10 00:11 完整 JPEG 联仿通过。测试使用实际三路编码器、原 FIFO、约90.025 MHz相机时钟、200 MHz编码时钟、QF90、两帧黑帽/黑帽+有效CLAHE和60fps输入节拍。每帧518,400个四像素拍，A/B/C均在下一输入帧前输出完整JPEG，三路各sent=2，预处理、JPEG和直方图fault/error均为0。其 PCIe 接收端设为始终可接收，因此不能覆盖真实 RK 背压；场景是生成的路面纹理和细暗线，不是相机抓图。

FIFO高水位A/B/C为217/217/433个四像素输入字，容量为256/256/512。这是两帧测试结果，实际高纹理场景、其他QF和RK背压仍需上板验收。日志为 `tools/ehp2_sim/jpeg/simulate.log`。

六张JPEG均成功解码为1920x360，按8行交错恢复为两张1920x1080图。纯黑帽帧与独立OpenCV参考的JPEG后平均绝对误差为2.5087灰度级，PSNR为38.0208 dB。黑帽+CLAHE图标准差由13.12提高到29.28，说明对比度增加；不能据此推断YOLO召回率改善。解码和参考比较记录为 `tools/ehp2_sim/jpeg/decode_report.json`，图像如下：

- [纯黑帽仿真JPEG重建图](tools/ehp2_sim/jpeg/reconstructed_blackhat.png)
- [黑帽后CLAHE仿真JPEG重建图](tools/ehp2_sim/jpeg/reconstructed_blackhat_clahe.png)

本合成场景下，纯黑帽三路JPEG总大小为552,180字节/帧，叠加CLAHE后为890,813字节/帧，增加61.33%。按60fps计，仅JPEG负载约33.13 MB/s和53.45 MB/s。CLAHE增强对比度也增强纹理，可能增加RK接收及解码成本；最终HDMI/YOLO帧率要分别实测，FPGA像素流水吞吐通过不能替代这项验证。

复现命令在工程根目录运行：

```powershell
python tools/check_sources.py
python tools/check_enhance_control.py
python tools/prepare_enhance_vectors.py
E:/FPGA/workspace/.tools/iverilog/bin/iverilog.exe -g2012 -s tb_gray_enhance4 -o sim/ehp2_small.vvp sim/tb_gray_enhance4.sv uisrc/01_rtl/gray_preprocess4.v uisrc/01_rtl/gray_gauss4.v
E:/FPGA/workspace/.tools/iverilog/bin/vvp.exe sim/ehp2_small.vvp
python tools/run_ehp2_sim.py pixels
python tools/run_ehp2_sim.py jpeg
python tools/verify_ehp2_jpeg.py
F:/FPGA/AnLu/bin/td_commands_prompt.exe tools/td_ehp2_synth.tcl
```

Python需要OpenCV、NumPy和工程现有静态检查依赖；本轮使用原训练虚拟环境。JPEG仿真runner仅在隔离副本中将第三方编码器的前向寄存器声明移到首次使用前，满足xsim的声明顺序要求，综合仍使用原源文件。

形态学底边复制排空已增加行间等待，沿用同帧观察到的最大无效拍间隔，减少尾部连续输出突发。不增加相机反压；仍须在下一帧 SOF 前排空。

首轮联仿复现 C 路输入FIFO满，故障为 `bridge=100 cause=8 line=355`，日志保留为 `tools/ehp2_sim/jpeg/before_gap_fix_failure.log`。首轮只在 EOL 后统计空隙；上游水平邻域的右侧前瞻会把最后一拍延迟到下一行，从而使真实空隙落在 EOL 之前，计数遗漏。修正为记录同帧所有无效拍间隔，并在底部复制行间使用其最大值；原 Gaussian 窗口逻辑保持。首轮综合报告保留为 `tools/ehp2_before_gap_fix_*`，最终综合另行覆盖 `tools/ehp2_*`。

## 最终综合资源与时序

2026-10-10 00:15，完整顶层综合、器件合法化和时序更新完成，退出码0，终端标记 `EHP2_SYNTH_PASS`，日志 `td_20261009_235938.log`。下表比较同一器件合法化阶段的EHP1/EHP2，不能与旧位流的最终物理占用直接作增量比较。

| 资源 | EHP1 同阶段 | EHP2 最终候选 | 容量 | 变化 |
| --- | ---: | ---: | ---: | ---: |
| Slice估算 | 48,848 | 46,292 (71.97%) | 64,320 | -2,556 |
| Slice寄存器 | 46,528 | 45,660 (35.49%) | 128,640 | -868 |
| ERAM20K | 256 | 256 (94.12%) | 272 | 0 |
| DSP | 122 | 122 (50.83%) | 240 | 0 |
| 分布式RAM LUT | 11,016 | 9,320 | 计入Slice | -1,696 |

黑帽分支本身ERAM从21降为13，分布式RAM LUT从4,608降为3,072。全预处理ERAM从25降为17；工具将释放的8块ERAM用于JPEG内部RAM，JPEG分支ERAM从110增为118。因此3x3共享方案实际节省整机Slice约5.23%，但本轮整机ERAM总数没有减少，不能声称又多出8块整机ERAM余量。剩余16块ERAM仍比较紧，后续扩容须看最终布线报告。

最终候选报告：`tools/ehp2_gate.area`、`tools/ehp2_legal.area`、`tools/ehp2_gate.timing`、`tools/ehp2_gate.ts`、`tools/ehp2_gate.db`。相机90.025 MHz域setup WNS **+0.324 ns**，STNS0；整机setup WNS **-0.744 ns**，STNS **-80.524 ns**，负裕量均在原200 MHz JPEG域。综合hold WNS0不代表布线hold已验收。

资源可容纳本次并行架构，像素及JPEG联仿已通过。上述为2026-10-10 00:15源码候选阶段的历史记录，当时尚未完成布局布线、bit生成、烧录及EHP2板测。此后用户已完成烧录，最终布线时序和板测结果见下节；综合阶段的负裕量不能代替最终物理时序结果。

## 手动综合与烧录验收

1. TD 打开 `fpga_prj_jpeg.al`，从 Synthesis 重新运行，随后布局布线。
2. 检查最终 Slice/ERAM 容量及各时钟 setup/hold，全部满足后生成并烧录 bit。
3. RK 更新控制脚本，读回 EHP2、位图FF、请求与生效模式，先恢复模式3。
4. 固定同一相机场景、焦距、QF、曝光和YOLO参数，逐一测试0..7模式。记录完整JPEG A/B/C帧数、重建FPS、HDMI实测呈现FPS、YOLO FPS和所有fault。
5. 黑帽重点验收B/C完整帧与FIFO故障；切换模式6/7等待CLAHE稳定，保存处理图及检测框。细裂缝召回必须使用人工标注，单凭框数量不能证明提升。

原板测 HDMI约56--57 FPS、重建约59 FPS；不能将“保留原视频性能”表述成已实现严格60 FPS。应与原模式3同场景比较，并以新位流长时间运行结果确认。

## 2026-10-10 EHP2 实板部署与测试

完整报告、图片和原始证据：[EHP2板测报告](../road_damage_yolov8n/runs/ehp2_board_20261010/REPORT.md)。

RK3576（2GB）经COM12控制，读回算法 `0x45485032`、位图 `0xff`。烧录后PCIe BAR/Mem/BusMaster配置丢失，通过endpoint移除重扫描及原驱动重载恢复收流。更新 `/root/jpeg_rk/preproc_mode.py`，原脚本已备份。使用原640×640 INT8模型，QF90、60fps输入选择、原软件JPEG解码3 workers、原时域仿射显示处理和YOLO interval2/conf0.10。

每模式12张实际相机图、25秒HDMI+YOLO运行，共96张和11,920个重建性能帧。全部模式预处理/raw/JPEG故障寄存器为0，未复现先前黑帽JPEG FIFO溢出。

| 模式 | 重建FPS | HDMI程序平均FPS | YOLO FPS | 未配对分片丢弃 |
| --- | ---: | ---: | ---: | ---: |
| 灰度 | 59.13 | 53.9 | 29.30 | 0 |
| 高斯 | 59.13 | 57.2 | 29.71 | 0 |
| CLAHE | 58.74 | 53.3 | 29.32 | 0 |
| 高斯+CLAHE | 59.13 | 56.7 | 29.51 | 0 |
| Sobel | 59.13 | 56.3 | 29.37 | 0 |
| 黑帽K3 gain1 | 58.85 | 54.1 | 29.55 | 0 |
| Sobel+CLAHE | 58.97 | 55.5 | 29.13 | 0 |
| 黑帽+CLAHE | 58.06 | 54.2 | 29.09 | 9 |

模式7的 `phase_mismatch=178` 是分片平均亮度差触发的启发式计数，并非178帧已确认错配。其平均JPEG负载492,484字节/帧，约为原模式3的2.15倍；负载增加可能影响接收/解码，但本轮未证明因果。严格60 FPS显示及零丢帧尚未通过。

另一次60秒连续运行中切换 `3→5→7→4→6→2→0→3`，全部模式读回生效，每5秒三路各发送299–300帧，无硬件故障或观察到的停流；全段重建3590帧，未配对丢弃0。

最终物理报告：Slice51,792/64,320（80.52%）、ERAM259/272（95.22%）、DSP122/240（50.83%）；setup WNS +0.093ns、hold WNS +0.020ns，STNS/HTNS为0。相比EHP1物理Slice54,257减少2,465，整机ERAM/DSP未减少。最终ERAM余量13块，区别于前述合法化阶段余量16块。

上述首轮实际画面为室内显示器/Windows桌面，用户当时暂时无法更换场景；首轮只能判断部署、通路和性能，不能判断道路细裂缝召回提升。图片中的检测属于该场景误检。首轮结束保持模式3/QF90/60输入及原HDMI+YOLO运行，原模型未替换。

## 2026-10-10 路面裂缝图片复测

用户已将相机对准路面裂缝图片。沿用原模型、QF90、60fps输入选择和YOLO interval2/conf0.10，再次完成八模式各12张及25秒性能测试，并做60秒动态切换。完整结果及图片：[路面复测报告](../road_damage_yolov8n/runs/ehp2_road_20261010/REPORT.md)。本轮共96张采样及11,820帧性能重建，硬件fault均为0。

| 模式 | 重建FPS | HDMI程序平均FPS | YOLO FPS | 未配对分片丢弃 |
| --- | ---: | ---: | ---: | ---: |
| 灰度 | 59.13 | 56.2 | 28.72 | 0 |
| 高斯 | 59.13 | 57.9 | 29.62 | 0 |
| CLAHE | 58.30 | 53.7 | 29.15 | 9 |
| 高斯+CLAHE | 59.13 | 55.6 | 29.46 | 0 |
| Sobel | 59.05 | 57.3 | 28.93 | 0 |
| 黑帽K3 gain1 | 59.17 | 55.0 | 28.60 | 0 |
| Sobel+CLAHE | 57.27 | 50.3 | 28.04 | 41 |
| 黑帽+CLAHE | 56.01 | 48.4 | 27.93 | 58 |

灰度、高斯和黑帽均能检出多处裂缝；黑帽增强后平均裂缝框（conf≥0.25）16.08，灰度16.92，高斯15.92，原默认15.50。这是框数观测，没有人工标注，不能当作召回率。CLAHE纹理增强未显示明确检测收益，增强后CLAHE的JPEG负载和配对损失增加；本轮黑帽+CLAHE平均612,082字节/帧。暂不建议据此改为长期默认。

60秒动态切换全部生效且无硬件fault，但接收段重建3548帧、未配对分片丢弃35；控制通过不代表零丢帧。结束恢复模式3/QF90/60输入及原HDMI+YOLO运行，原模型未替换。此节结果对应道路图片，与上节室内场景结果分别保留。

## 2026-10-10 RK按键与显示更新

RK已新增左上角第三行 `PREPROC`，显示 `0x100` 回读的实际生效模式。K1（GPIO47，低有效）短按松开继续切换QF，长按约1.2秒循环切换0..7预处理，持续按住只触发一次，松开不追加QF动作。当前恢复模式3/QF90。无需重新烧录bit。

状态图层600×124、1Hz刷新；实际八模式切换及显示回读通过，QF保持90、硬件fault均0。按键逻辑防抖/长短按回放通过，物理按键最终反馈待用户确认。详细说明、缓冲图、安装备份及验证证据：[K1与状态显示部署记录](../road_damage_yolov8n/runs/k1_preproc_20261010/DEPLOY.md)。

## 2026-10-10 RK程序发布归档

已从板端当前运行目录采集47个部署文件，包含模型、NPU运行库、PCIe/JPEG驱动、EHP2控制、K1长短按和PREPROC显示，保存为 [RK发布ZIP](../road_damage_yolov8n/releases/rk3576_yolov8n_ehp2_k1_20261010.zip)。ZIP大小5,927,137字节，SHA256 `0d8c4753aff5134bdc2ed04e94ee6484451da5593ae1310f2e9c98d0450debe3`，已核对板端传输、47个内部文件及ZIP完整性。

包内保存实际运行环境、源代码、K1/道路验证摘要和恢复启动步骤；[发布说明](../road_damage_yolov8n/releases/rk3576_yolov8n_ehp2_k1_20261010/README.md)。这是匹配RK3576/Linux6.1.99环境的程序与驱动快照，不含FPGA bit或RK系统镜像，未实际执行恢复。旧2026-10-08版本保留。
