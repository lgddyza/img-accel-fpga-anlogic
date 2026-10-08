# RK 到 FPGA 参数控制：第一阶段

## 结论

板卡能够完成图中第一阶段参数控制。PCIe SGDMA 已经提供 AXI-Lite user BAR，这就是独立于 JPEG C2H 视频流的低带宽控制通道，不需要再占用一条 H2C DMA 通道。当前布局使用 40382 slices（62.78%），setup/hold 余量为 +0.173 ns/+0.020 ns；增加参数寄存器、状态回读和握手只需要很少逻辑。

Gaussian 和 HE 已经同时存在于活动 RTL 中，`0xA4` 当前支持 gray、gauss、he、all 四种组合，因此开关它们不需要复制算法核。Gaussian 的 Weak/Medium 尚未实现：当前只有固定强度 Gaussian。后续可用原图与 Gaussian 输出的加权混合实现 Weak，继续使用现有 Gaussian 输出作为 Medium，通常不需要新增行缓存。

## 第一阶段范围

- JPEG QF 请求值：1 到 100；界面首选项为 30/40/50/60/70/80/90。
- 支持停止采集后修改，也支持 `--live` 在完整帧之间修改。
- 三个 JPEG 核全部完成量化表更新后，才报告 applied QF。
- 不改变 JPEG C2H1/C2H2/C2H3 数据格式，不改变当前预处理算法。

## BAR 寄存器

| 地址 | 方向 | 含义 |
| --- | --- | --- |
| `0xB8` | R/W | requested QF，合法范围 1..100 |
| `0xB4[3]` | R | 三个 JPEG 核均 configured |
| `0xF8[6:0]` | R | applied QF |
| `0xF8[7]` | R | applied QF 有效，等同于三个核 configured |
| `0xFC` | R | 控制 ABI 标签 `0x4A435431`（`JCT1`） |

旧 bit 的 `0xF8/0xFC` 返回 0。新版 RK 工具会兼容旧 bit，但只能根据等待时间和 configured 状态推断 QF 已生效；新 bit 可精确比较 requested 与 applied。

## RK 使用

状态查询：

```bash
python3 /root/jpeg_rk/jpeg_control.py
```

停止 JPEG 接收后设置：

```bash
python3 /root/jpeg_rk/jpeg_control.py --quality 70
```

HDMI 持续运行时在线设置：

```bash
python3 /root/jpeg_rk/jpeg_control.py --quality 70 --live
```

工具会等待三个编码器完成配置；超时、BAR 回读不一致或 FPGA fault 都应视为设置失败。

## 已完成验证

- `tb_jpeg_axil_config` 验证 QF 不会在活动帧中途改变，并验证 applied QF 只在配置事务完成后更新。
- `tb_jpeg_quality_handshake` 验证三个核从 Q85 切换到 Q50、再切换到 Q90 时，ready 先撤销，三区 applied QF 一致后才恢复。
- 200 MHz 三路连续 JPEG 回归通过，A/B/C 均发送 3 帧、fault=0。
- 工程静态检查通过：106 个源/IP/约束文件、29 个本地命名端口连接、所有活动预处理/JPEG RTL 语法检查。
- 当前旧 bit 板测：停止采集后 Q30 和 Q90 均完成三路 JPEG 编码和解码，故障为 0；相同现场短序列中三路合计帧大小约从 Q30 的 28.0 KB 增至 Q90 的 32.0 KB。
- 当前旧 bit 在线板测：Q85 -> Q50 -> Q90 -> Q85，HDMI 进程保持运行，三路发送计数始终相等、未配对为 0、FPGA fault 为 0。

## 2026-10-06 新 bit 上板结果与 K1 手动控制

- 烧录后重绑 RK PCIe 控制器，`0xFC` 读到 `JCT1`，上电 Q85 requested/applied 一致，三路 configured=111，fault=0。
- 停止采集时依次写入 Q30/40/50/60/70/80/90，全部返回相同的 applied QF，最后恢复 Q85。
- HDMI 运行中切换 Q30→Q90→Q85，三路帧计数始终相同，fault=0；约 3 秒稳定后，Q30 三路 JPEG 合计最近帧 63,854 字节，Q90 为 285,157 字节。该比值取决于现场画面，不是固定压缩率。
- HDMI 解码重建累计约 59.96 FPS；实际 HDMI sink 秒级值约 55–59 FPS，仍受 RK 侧 CPU 调度影响。
- 底板普通按键 K1 连接 RK3576 GPIO1_B7（Linux GPIO 47），1.8 V 上拉、按下为低电平；现场实测记录到 `1→0→1`。RK `jpeg_qf_button.py` 防抖后按 Q30/40/50/60/70/80/90 循环切换，并等待 `JCT1` applied 回读。`start_jpeg_hdmi_60.sh` 启动 HDMI 时一并启动此控制器；按键日志在 `/root/jpeg_rk/qf_button.log`。HDMI 左上角显示 applied QF。
- 用户现场按 K1 后确认 HDMI 显示从 `QF:85` 切到 `QF:90`，画面连续；RK 日志随后记录 `90→30→40` 的按键切换，OSD 同步更新且最新 sink 约 60 FPS。
- K1 属于 RK 侧按键，当前 FPGA RTL 中相机 AE 的 `I_btn` 仍固定为 `2'b11`，不会与 K1 冲突。

手动运行独立探针（只读电平，不改 QF）：

```bash
python3 /root/jpeg_rk/jpeg_qf_button.py --probe-seconds 20
```

## 新 bit 验收

1. 停止 viewer，烧录新 bit，重新绑定 PCIe 后确认 `0xFC = 0x4A435431`。
2. 对 30/40/50/60/70/80/90 逐项写入，要求 requested QF 与 applied QF 相同。
3. 每档固定相机和光照抓取至少 30 组 JPEG，记录平均字节数、码率、PSNR/SSIM 和裂缝边缘保真度。
4. viewer 运行时往返切换 30/90 至少 100 次，要求三路计数相等、fault=0，并记录显示端掉帧。

当前共同未知是在线切换对 HDMI 显示队列的瞬时影响。旧 bit 测试期间 FPGA 接收和重构保持 60 FPS，但 RK 的秒级 HDMI sink 统计出现短时下降；板上同时有三个接近满核的 SGDMA polling 线程。新 bit 验收时需要把 FPGA 控制握手和 RK 调度压力分别记录。
