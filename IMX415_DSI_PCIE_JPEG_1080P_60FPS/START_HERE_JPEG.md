# IMX415 DSI + PCIe JPEG 1080P/60 工程

这是从 `IMX415_DSI_PCIE_GRAY_1080P` 独立整理出的 JPEG 版本。原工程未被删除或覆盖。

## 2026-10-07 新 bit 上板与 QF 扫描

用户报告已烧录新 bit。RK 端重新绑定 PCIe 后回读 `JCT1`、模式 3、60 FPS；QF30～90 七档各 180 组完整三路 JPEG 的实际接收与样张比对已完成，FPGA faults=0。码率图、画面拼图和完整数据见 `captures/qf_sweep_20261007/README.md`。当前已恢复 QF85 和 HDMI 实时显示。接收/重建约 60 FPS，但 HDMI 图层约 57～59 FPS，不能混为同一个帧率。控制 BAR 没有单独的 IIR 位流版本号，所以此轮确认视频/QF 通路，不单凭寄存器证明 IIR 已进入烧录文件。

同日第二轮在道路与护坡画面下重复七档测试，各档同样完成 180 组三路配对、约 60 FPS、faults=0；场景纹理更多，QF90 平均码流升至约 380.9 KB/帧。新拼图和逐档数据在 `captures/qf_sweep_repeat_20261007/README.md`。恢复 QF85 后，JPEG 重建约 59.91 FPS，HDMI 图层平均约 54 FPS，显示瓶颈仍在 RK 端。

## 2026-10-06 HE IIR 候选

活动 RTL 已为直方图均衡 LUT 加入 1/4 帧间 IIR，意在减轻室内灯光下被上一帧 LUT 放大的明暗交替。Vivado xsim 的小帧和完整 1080p 检查通过；`verified_output/fpga_prj_jpeg.bit` 仍是旧基线，不能把它当作新候选。用户报告的新 bit 已进行以上 QF 通路测试，IIR 对闪动的单变量效果尚需另测。实验设计见 `HE_TEMPORAL_IIR_EVALUATION_20261006.md`。

## 2026-10-06 RK HDMI 状态

当前板上为 FPGA 模式 3、QF90、JPEG 三路 60 FPS；RK 使用逐帧亮度与对比度联合校正、6 帧显示缓冲和 CPU 分配。用户观察 HDMI 摄像画面的黑闪已比之前明显减轻；Gaussian-only 模式连续超过 1 分钟完全没有异常，说明直方图均衡及灯光频闪是主要触发因素。实际测量中 JPEG 三路接收与重建约 59.9 FPS，HDMI 图层呈现随场景约 54～59 FPS，短时低至约 44 FPS，仍不能宣称在所有场景稳定显示 60 张不同图像。详细实验见 `BOARD_TEST_HDMI_STABILITY_20261006.md`。

## 正确入口

- TD 工程：`fpga_prj_jpeg.al`
- 顶层：`system_top`
- FPGA：PH1A90SEG324-2
- 已验证位流：`verified_output/fpga_prj_jpeg.bit`
- RK 部署包：`deploy/jpeg_rk_bundle.zip`

不要把 `archive_pre_jpeg` 中的文件作为当前工程入口。该目录只用于保留 JPEG 接入前的项目清单。

## 当前数据通路

1. IMX415 输出 1920x1080 RAW10，FPGA 完成 ISP 和 GREY8 转换。
2. 预处理模式 3 依次启用 Gaussian 和上一帧直方图均衡。
3. FPGA 将一帧按 8 行交织分为 A/B/C 三个 1920x360 灰度 JPEG。
4. JPEG A/B/C 分别通过 PCIe C2H1/C2H2/C2H3 传到 RK；C2H0 保留原始 GREY8 调试流。
5. RK 解码三路 JPEG，重新交织为 1920x1080，并经过 NEON 逐帧亮度／对比度校正与两帧融合后送 HDMI。

当前板上 JPEG 参数为 Baseline grayscale、QF90；K1 可循环切换 30～90。位流上电或 PCIe 端点复位后默认 30 FPS，RK 必须在停止接收时执行：

```bash
python3 /root/jpeg_rk/jpeg_control.py --rate 60
```

RK 端推荐使用已验证的一键启动命令：

```bash
sh /root/jpeg_rk/start_jpeg_hdmi_60.sh 188
```

该脚本将 CPU governor 设为 `performance`，按源码校验并构建滤镜，把 FPGA JPEG 速率切到 60 FPS，关闭 RK 桌面合成，并让三线程软件 JPEG 解码与 NEON 联合校正运行在避开 SGDMA 接收线程的 CPU 上。HDMI 左上角实时显示实际图层帧率、`1920x1080` 和 QF。停止显示后可执行 `sh /root/jpeg_rk/set_video_governor.sh ondemand` 恢复动态调频；若要恢复 XFCE 桌面合成，可执行 `sudo -u linaro env DISPLAY=:0 XAUTHORITY=/home/linaro/.Xauthority xfconf-query -c xfwm4 -p /general/use_compositing -s true`。

## 手动综合

1. 关闭仍打开原目录工程的 TD 窗口。
2. 打开本目录的 `fpga_prj_jpeg.al`，确认工程路径显示为本目录。
3. 顶层保持 `system_top`，器件保持 PH1A90SEG324-2。
4. 依次执行综合、布局布线、bit 生成。
5. 检查 setup/hold 均无违例，再烧录新生成的 bit。

本目录没有复制旧的 `fpga_prj_jpeg_Runs` 活动缓存，首次综合会创建新的 Run，避免引用原目录的绝对路径。上一次板上验证结果单独保存在 `verified_output`。

## 2026-10-05 验证基线（历史数据）

- 时序：SWNS +0.173 ns，HWNS +0.020 ns，STNS/HTNS 均为 0。
- FPGA JPEG：三路约 60 FPS，故障计数 0。
- RK HDMI：约 59.9 FPS，三路未配对帧为 0，去闪启用。
- RK 优化复测：60.2 秒重建 3597 帧，平均 59.93 FPS；软件解码 8.9 ms/帧、交织 1.8 ms/帧、两帧融合约 1.29 ms/帧，板温 46.2 摄氏度。
- 原始 GREY8：2,073,600 B/帧，60 FPS 时 995.328 Mbit/s。
- 当前场景 Q85 JPEG：平均 253,512.5 B/组，约 121.7 Mbit/s，压缩比约 8.18:1。

JPEG 大小随路面纹理、噪声、照明和运动变化。最终压缩传输时不要打开 C2H0 原始流，否则 PCIe 上会同时传输原始与压缩数据。

两帧平均适合当前以静态道路裂缝为主的航拍方向，能消除相邻帧亮度交替且开销较低。快速运动时可能产生一帧长度的轻微重影；需要比较时可直接运行 `show_jpeg_hdmi.py ... --temporal-method tone`，其运动重影更少但处理开销更高。

## 目录说明

- `uisrc`：当前 FPGA RTL、约束和厂商 IP。
- `third_party/mjpegZero`：JPEG 编码核及上游说明。
- `al_ip`：PCIe 和时钟相关 IP。
- `sim`：预处理、JPEG 桥接、三分片和连续帧仿真。
- `deploy`：RK V4L2 驱动、JPEG 接收/解码/显示、控制与测量程序。
- `tools`：工程检查、仿真、打包和图像分析工具。
- `verified_output`：已经综合并上板验证的 bit、时序和 QOR，不作为新综合缓存。
- `archive_pre_jpeg`：JPEG 接入前的项目清单，仅用于追溯。
- `captures`：历史抓帧和视觉分析证据。

详细板测见 `BOARD_TEST_JPEG_60_20261004.md`；整个开发状态和寄存器说明见 `PROJECT_HANDOFF.md`。

RK 到 FPGA 参数控制的第一阶段接口、QF 命令和新 bit 验收步骤见 `CONTROL_CHANNEL_STAGE1.md`。
