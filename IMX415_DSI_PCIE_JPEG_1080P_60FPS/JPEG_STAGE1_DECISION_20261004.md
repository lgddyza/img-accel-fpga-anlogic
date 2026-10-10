# JPEG 第一阶段：选型、实测和接入边界（2026-10-04）

> 历史选型记录。文中的单核隔帧接法已被 `JPEG_TRIPLE_TILE_INTEGRATION_20261004.md` 替代：选中摄像头帧的活动行仍在 16.7 ms 内到达，单核即使平均速率够 30 FPS，也无法不经整帧缓存吸收这段突发。下文的单核资源和 150 MHz 结论仅属于当时的独立实验。

## 目标和本阶段交付

目标是保留现有 IMX415→DSI 与 FPGA→RK→HDMI 约 60 FPS 的预览，同时增设 FPGA 硬件 JPEG 支路，最终把可变长压缩帧送到 RK 做保存、显示和裂缝推理。本阶段完成候选源码检查、独立安路综合、真实抓帧 RTL 仿真、灰度格式转换、四像素跨时钟序列化及小帧 JPEG 联合仿真；**当前板上位流和原 GREY8 PCIe/RK 驱动未修改，尚不能声称 JPEG 已上板传输。**

## 候选比较与决定

| 候选 | 实际特征 | PH1A90 独立门级估算 | 决定 |
| --- | --- | --- | --- |
| [lulinchen/jpeg_open](https://github.com/lulinchen/jpeg_open) | MIT；1080P 编码演示；输入为单像素 UYVY/相机时序；固定 Q50；本地两帧真实灰度抓帧能解码。内部用了深 RAM 包装、250/300 MHz 风格的双计算时钟。 | YUV422：2,927 Slice、45 ERAM、52 DSP | 留作高速吞吐与 MIT 许可备选，不先接入现有系统。|
| [lcapossio/mjpegZero](https://github.com/lcapossio/mjpegZero) Lite | AXI4-Stream 输入带 `tready`；完整 JFIF 输出；Q85 在综合时固定；公开目标 1080p30/150 MHz。 | 1080p/Q85：1,943 Slice、58 ERAM、17 DSP | 验证参考。|
| **mjpegZero Full** | 运行时可从 AXI-Lite 改 Q75/85/95，方便裂缝质量试验；输入、输出和错误边界较清楚。 | **1080p：2,256 Slice、61 ERAM、19 DSP** | **首个端到端 JPEG 支路选用**，先验证 1080p30 压缩支路，预览链保留 60 FPS。|

Full 比 Lite 多约 313 Slice、3 ERAM、2 DSP，值得换取无需重新烧录即可调节画质。mjpegZero 的 LICENSE 是 Apache-2.0 加 Commons Clause；学生、研究、非商业使用明确许可，未来如商业化需要取得作者许可或换核。第三方源码及许可证在 `third_party/mjpegZero/`，尚未加入 `fpga_prj.al`，避免影响当前可用位流。

现有最新布线使用 24,503/64,320 Slice、120/272 ERAM、36/240 DSP；与 Full 核**算术相加**为 26,759 Slice、181 ERAM、55 DSP，剩余 37,561 Slice、91 ERAM、185 DSP。尚未计入 4→1 跨时钟缓冲、字节打包、PCIe 协议和控制，因此这不是最终布线占用，也没有时序保证。剩余 ERAM 只有约 228 KiB，放不下一整张 1080p GREY8 帧；必须用行缓冲、流式发送或外部 DDR。

## 已验证的东西

1. 安路 TD Release_2026.1_SP2 对两套候选都完成独立 `optimize_rtl` 和 `optimize_gate`；详细日志和面积文件在 `E:/FPGA/workspace/jpeg_rtl_evaluation/`。该直接读入源码的实验没有完整的项目时钟约束，不能从其默认时序报告推出 150/200/300 MHz 可达。
2. `jpeg_open` 用真实摄像头抓帧 `before_1.png`、`after_1.png` 各编码一帧，软件解码均为 640×360。后处理帧 Q50 为 26,814 字节，MAE 4.207、PSNR 32.691 dB。
3. `mjpegZero` Full 在运行时设置 Q85，真实后处理帧输出有效 JFIF JPEG，55,455 字节，相对 230,400 字节 GREY8 为 4.155×；MAE 2.712、PSNR 36.951 dB。Lite/Q85 同帧输出的 JPEG 与 Full/Q85 的 SHA-256 完全一致。64×8 小帧和 640×360 抓帧的仿真都通过，后者用 Pillow 独立解码核验。
4. `uisrc/01_rtl/gray4_to_yuyv4.v` 把现有四路 `{0,Y,Y,Y}` 灰度数据转换为四路 `{8'h80,Y}`，保持 SOF/EOL。独立仿真 `GRAY4_TO_YUYV4_PASS`。它**只转换格式**，不承担速率匹配。
5. `uisrc/01_rtl/jpeg_gray4_axis_cdc.v` 用已有的 `demo_async_sfifo` 实现 72→18 bit、四像素→单像素的跨时钟输出，保留首像素 SOF 和每行末尾 EOL；仅在输入 SOF 时选帧。源数据无背压，故模块核验每行节拍和总行数，遇格式错误或 FIFO 溢出时锁存故障、停止 AXI 输出，要求上层丢弃正在形成的 JPEG 并同时复位桥和编码器。正常帧、跳帧、停读溢出仿真均通过（`JPEG_GRAY4_CDC_FRAME_PASS`、`JPEG_GRAY4_CDC_OVERFLOW_PASS`）。现有 FIFO 的 show-ahead RAM 是同步读出，桥中增加了首次读数有效的保护。
6. 把该桥直接接到 `mjpegZero Full`，64×8 灰度小帧 Q85 联合仿真输出 744 字节 JPEG，出现 SOI/EOI，Pillow 独立解码为 64×8 RGB（`JPEG_BRIDGE_ENCODER_PASS`）。这是接口和数据顺序验证，不是 1080p 性能验证。
7. 安路 TD 对桥及窄 IO 综合包装独立映射通过：约 231 Slice、2 ERAM、0 DSP（含小包装逻辑）；和现有项目、Full 核算术相加约 26,990 Slice、183 ERAM、55 DSP，尚不包括 JPEG 输出缓冲、打包、控制、实际项目布线。

这些数值来自室内抓帧，不是道路裂缝检测效果。PSNR 不能替代细裂缝召回率。先前道路图集的软件 GREY8 JPEG Q85 码率也不能直接作为这个三分量 YUV422 硬件核的码率实测。

## 下一阶段的具体接法

```text
现有预处理 4 像素/拍 ─┬─ 现有原图 GREY8 PCIe→RK→HDMI（保留）
                      └─ gray4_to_yuyv4 ─ 帧选择/跨时钟行 FIFO/4→1 序列化
                                               └─ mjpegZero Full(Q 可调)
                                                    └─ 输出 FIFO/16 字节打包/帧协议
                                                         └─ PCIe→RK JPEG 接收与解码
```

预处理源没有背压，编码器只有 1 像素/拍且可以拉低输入 `tready`，**不能直接接线**。先在压缩支路按 SOF 完整选帧，目标隔帧压缩 30 FPS；选中帧需用能处理活动行突发的双时钟 FIFO。若 FIFO 溢出，只能把该帧标为失败并整帧丢弃，不能把截断 JPEG 当作正常帧交给 RK。等待编码器空闲再选下一帧，预览支路不受帧选择影响。待全链稳定后再尝试提高压缩帧率。

JPEG 输出逐字节、长度未知且无 `tready`。PCIe 现有通路是固定 2,073,600 字节 GREY8，RK V4L2 驱动也按这个长度处理；必须增加帧序号、宽高、质量、有效长度、状态/校验的可变长帧协议。可先流式发负载并在帧尾放长度与校验，16 字节总线最后一拍补齐；RK 仅在完整帧尾和 JPEG EOI 验证通过后发布 `bytesused`。PCIe 长暂停时须检测 FIFO 溢出、丢弃当前帧并重新同步。原 GREY8 模式继续作为演示与回退。

## 需要用最小实验消除的未知

| 未知 | 单变量实验 | 通过信号与回收数据 |
| --- | --- | --- |
| 整机是否有足够时序余量 | 将 Full 核、FIFO 和打包器接入独立工程后，仅改变编码时钟目标；先 150 MHz。 | TD 完整布线 WNS≥0、无 FIFO 溢出；记录 Slice/ERAM/DSP、时钟、最差路径。独立门级面积不算通过。 |
| 30 FPS 乃至 60 FPS 是否能持续编码 | 固定 1080p 输入和 Q85，只改变选帧比例/编码时钟。 | 连续至少 10 分钟统计输入帧、选中帧、完成帧、失败帧、字节数、最大 FIFO 占用；RK 解码与帧序号一致。先达到稳定 30 FPS，再挑战 60 FPS。 |
| JPEG 会否损伤细裂缝 | 相同航拍测试集和 NPU 模型，只改变 Q75/85/95。 | 按裂缝宽度分层记录召回率、误报、压缩长度与推理耗时；Q85 失召回则调 Q95 或改 ROI 方案。 |

下一次项目集成应把已独立仿真的格式转换、跨时钟桥、Full 核接到预处理旁路，并实现外层的选帧/故障复位控制，再完成项目级布线与时序。`s_take_frame` 必须仅在 SOF 为整帧给出；桥故障后由控制器丢弃正在生成的压缩帧，同时复位桥和编码器。随后做 JPEG 输出 FIFO、PCIe 变长包和 RK 解码显示。现有 GREY8 显示通道继续工作。
