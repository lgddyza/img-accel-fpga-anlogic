# JPEG 60 FPS 候选版本（2026-10-04）

## 目标与当前结论

目标是 FPGA 每秒产生约 60 组**不同相机帧**的 A/B/C JPEG，RK 解码交织成 1080p，再送 HDMI。重复同一 JPEG 帧只用于 RK 负载测试，不计入验收。

当前板上旧 bit 的 RTL `jpeg_triple_tile_branch.v` 在每个 SOF 翻转 `frame_phase`，`a_take=arm_cam[1] && !frame_phase`，明确隔帧选取，导致三路 JPEG 约 30 FPS。RK 串行解码约 20.7 ms/组，无法处理 60 FPS；改成三路并行软件解码后，旧 bit 下 30 秒实测三路接收 899/898/898、重建 898，未配对 0，解码约 9.3 ms/组、拼接 2.5 ms、送帧 4.0 ms。

`--benchmark-repeat 2 --fps 60` 对每组旧 bit 的 JPEG 数据重复解码和送屏两次，20 秒得到 598 组**不同**数据、1196 次重建送屏，HDMI sink 约 59.7–60.3 FPS，三路未配对 0。这证明 RK 在此场景有约 60 次/秒的软件处理能力；并未证明 FPGA 已产生 60 组不同 JPEG。测试结束已恢复当前旧 bit 的三路并行 30 FPS JPEG HDMI 预览。

## FPGA 候选改动

- `jpeg_triple_tile_branch.v` 增加 `full_rate` 输入。默认 0 时保留已验证的隔帧 30 FPS；置 1 后每个相机 SOF 都有资格选取一帧，但仍要求三路编码器、DMA、配置与链路都 ready，不能用缓冲溢出来伪造 60 FPS。
- `system_top.v` 新增 BAR `0xF0` 控制位（0=30、1=60）和 `0xF4=0x4A503630`（“JP60”能力标签）。上电默认 30；不改变旧 JPEG ABI 3 与驱动格式。
- `jpeg_control.py --rate 60` 只在读到 JP60 标签且 JPEG 采集停止时才允许写。RK 显示脚本增加三路并行解码及 `--fps 60` 输出参数，默认运行仍不重复帧。
- TD `td_commands_prompt.exe tools/td_jpeg_elaborate.tcl` 已通过 `elaborate -top system_top`。**未做完整综合、布局布线、bit 生成或新位流上板测试**；按用户习惯由用户在 `fpga_prj_jpeg.al` 手动综合。

## 主要风险与最小上板实验

旧 bit 上板采样显示，JPEG `busy` 中位时长约 16.351 ms，空闲约 16.984 ms；旧模式的编码周期间隔约 33.3 ms。要每 16.7 ms 抓一帧，上一组完成到下一相机 SOF 的余量可能只有约 0.3 ms，受画面复杂度、PCIe 背压和时钟抖动影响，仍可能自动跳帧。这是候选改动需要板测的核心未知。旧 bit 的 200 MHz JPEG 时钟布局 SWNS 仅 +0.019 ns，改 RTL 后必须检查时序，不应直接烧录一个负裕量 bit。

建议单变量实验：用新 bit、Q85、同一相机场景，先保持 BAR `0xF0=0` 复验原 30 FPS；停止采集后写 `jpeg_control.py --rate 60`，再以 `show_jpeg_hdmi.py --decoder software --decode-workers 3 --fps 60` 运行至少 60 秒。检查 A/B/C 发包增量是否各约 3600、故障是否 0、RK `distinct` 是否约 3600、`unpaired` 是否 0、HDMI sink 是否约 60 FPS。若 FPGA 发包只有 30–50 FPS而无故障，说明 busy 门控赶不上逐帧 SOF；若出现 FIFO/packer 故障，需定位 C 路缓冲与背压。测试失败时停采集并写 `--rate 30` 回到基线，不必重新烧录。

当前板上仍是旧 bit，`jpeg_control.py` 明确打印 `rate mode: fixed 30 FPS (old bitstream)`，因此尚不能宣称真实 JPEG 60 FPS 达成。
