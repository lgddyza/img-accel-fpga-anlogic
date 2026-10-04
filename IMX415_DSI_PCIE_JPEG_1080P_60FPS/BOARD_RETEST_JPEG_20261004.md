# 新位流 JPEG / RK 复测（2026-10-04）

**历史故障记录：**C 路已在后续 20:37 位流中恢复，并通过 120 秒三路并行板测。最新结论见 `BOARD_VERIFY_JPEG_C_20261004.md`。

新位流 `fpga_prj_jpeg_Runs/best_result/fpga_prj_jpeg.bit` 生成时间 17:40。烧录后重新枚举 PCIe，BAR `0xB0=0x3347504a`，诊断寄存器 `0xE8` 可读。布局报告 JPEG 200 MHz 时钟 SWNS `+0.159 ns`、STNS `0`。以下为板端实际采集结果；每路原始单色数据为 1920×360×1 = 691,200 字节。

| 条件 | A JPEG | B JPEG | C JPEG | 10 秒内完整三路组合 |
| --- | ---: | ---: | ---: | ---: |
| Q85，HDMI 同时运行 | 85,810 B，8.05:1 | 85,072 B，8.12:1 | 0 B | 0 |
| Q50，HDMI 同时运行 | 46,258 B，14.94:1 | 45,466 B，15.20:1 | 0 B | 0 |
| Q85，停止 HDMI | 85,563 B，8.08:1 | 85,136 B，8.12:1 | 0 B | 0 |

A/B 均为合法 JFIF baseline、8 bit、单通道 1920×360 JPEG。Q85 第一组的 A/B 已分别经 RK GStreamer `jpegparse ! jpegdec` 解码通过，文件在 RK `/root/jpeg_rk/retest_q85/unpaired_a.jpg` 和 `unpaired_b.jpg`。Q50 文件在 `/root/jpeg_rk/retest_q50/`。由于 C 缺失，未生成完整 1920×1080 图，不应把 A/B 压缩率当作全帧传输结果。

三次试验的首次故障状态一致：`bridge_fault=100`、`packer_fault=000`、`configured=111`、`input_seen=111`、`jpeg_byte_seen=111`、`jpeg_eoi_seen=011`。这些三位值的最低位是 A，最高位是 C。因此 C 已收到输入帧起点并产生部分 JPEG 字节，但 **C 输入桥报错且未产生 EOI**；A/B 均完成。BAR `sent_A/B/C=1/1/0`、`faults=1`。`bridge_fault` 当前合并了输入行格式异常与输入 FIFO 满，尚不能据此二选一。Q50 和停止 HDMI 均未排除故障。

测试结束后将 C 模块 `recover_on_error` 恢复为默认 `1`，复位 JPEG 支路并恢复 Q85；BAR 当前空闲、故障清零。灰度 HDMI 预览重新启动，日志约 59–60 FPS。下一步应给 C 输入桥分别记录 `malformed`、`fifo_overflow` 和已接收行数，再决定是修正实机行同步/分带，还是提高 C FIFO/编码吞吐。一次只改动诊断逻辑，避免在未知根因时盲目扩容 FIFO。
