# JPEG C 路修复候选与上板验证

**验证更新：**用户已烧录本次改动，三路 JPEG 和 1080p 拼接上板通过；见 `BOARD_VERIFY_JPEG_C_20261004.md`。下文保留修复前的假设与测试计划。

## 已知故障

新位流（17:40 生成，JPEG 200 MHz SWNS +0.159 ns）在 RK 上的 Q85、Q50、关闭 HDMI、原灰度预处理模式下，都只收到 A/B 一帧，C 零帧。`0xE8` 显示 C 收到帧起点、产生部分 JPEG 字节，但输入桥故障且没有 EOI。故障同一次发生时，原灰度 C2H0 的 `capture_errors` 维持 284 不变，排除了该时段整条摄像头输入同时坏帧的证据。现有诊断把行格式异常和 FIFO 满合并，不能确定其一。

## 本次源码修改

- 仅 C 路的 `jpeg_gray4_axis_cdc` 输入 FIFO 从 256 增至 512 个 72-bit 写字；A/B 不变。这是针对 C 独有输入桥故障的候选修复，不应在实测前认定生效。
- `jpeg_gray4_axis_cdc.v` 锁存首次故障原因和位置：cause bit0 意外新 SOF、bit1 行结束位置错误、bit2 超出 360 行、bit3 FIFO 满。对应输出接到 `jpeg_triple_tile_branch.v`，BAR 新增 `0xEC`：bit0–3=C cause、bit4–13=C 已接收行数、bit14–23=C 行内四像素字位置、bit24–27=B cause、bit28–31=A cause。
- RK `/root/jpeg_rk/jpeg_control.py` 已更新，读新位流时会输出 `first input fault`。现在烧录的旧位流没有 `0xEC` 实现，必须重新生成位流后才有意义。

## 已完成验证

- 1920×1080、90 MHz 摄像头时钟、200 MHz JPEG 时钟、高纹理随机输入的旧 256 深度三路仿真通过：A/B/C 分别 466,450 / 466,615 / 466,384 字节，表明单靠正常满帧仿真不能复现板上问题。
- 新的输入桥故障分类小测试通过：提前新 SOF 与输入 FIFO 满能分别锁存正确原因；日志 `E:/FPGA/workspace/jpeg_rtl_evaluation/jpeg_fault_detail_xsim.log`。
- C 512 深度后的三路连续帧仿真通过 `sent=2/2/2`；日志 `E:/FPGA/workspace/jpeg_rtl_evaluation/triple_cfifo_xsim.log`。
- 安路 TD 仅执行源码读取和 `elaborate -top system_top`，通过 `JPEG_PROJECT_ELABORATE_PASS`，推断 RAM 由 97 增至 98。**尚未完整综合、布局布线或生成新位流。**

## 手动综合及复测

1. 在 TD 打开 `fpga_prj_jpeg.al`，完整综合、布局布线并生成新位流。检查 ERAM <272、JPEG 200 MHz 时钟 SWNS≥0，记录最差路径。不要沿用 17:40 的旧位流。
2. 烧录后通知我。我会重枚举 RK PCIe，并在 Q85、灰度 HDMI 同时运行时采集三路至少 10 组。首轮将 C 驱动 `recover_on_error=0`，便于故障时读取 `0xE8/0xEC`；通过后恢复默认自动复位。
3. 若 C 输出有效，检查三个 1920×360 JPEG 均可解码，拼接 PGM 为 1920×1080，A/B/C 帧数一致、`faults=0`，再做 10 分钟压力测试。若 C 再故障，依据 cause 和位置只修改对应路径：bit3 验证 FIFO 是否仍满；bit0/1/2 查分带或末行几何，不能继续盲目增加 FIFO。
